// SPDX-License-Identifier: MIT
pragma solidity 0.8.18;
import {DecentralizedStableCoin} from "./DecentralizedStableCoin.sol";
import {ReentrancyGuard} from "@openzeppelin/contracts/security/ReentrancyGuard.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {AggregatorV3Interface} from "@chainlink/contracts/src/v0.8/interfaces/AggregatorV3Interface.sol";

/**
 * @title DSCEngine
 * @author Aayush Gupta
 * @notice The system is designed to be as minimal as possible and have the tokens maintain a 1 token == $1 peg.
 * This stablecoin has the properties:
 * - Exogenious Collateral
 * - Dollar Pegged
 * - Algorithmically stable
 *
 * It is similar to DAI if DAI had no governance, no fees and was only backed by  wETH and wBTC
 *
 * Our DCS system should always be "overcollateralized". At no point, should the value of all collateral  <= the $ backed value of all DSC.
 *
 * @notice This contract is the core of the DSC system, It handles all the the logic for mining and redeeming DSC, as well as depositing & withdrawing collateral.
 *
 * @notice This contract is Very lossely basedon the MakerDAO DSS (DAI) system
 */
contract DSCEngine is ReentrancyGuard {
    ///////////////////////////////////////////
    //////////        Errors     //////////////
    //////////////////////////////////////////
    error DSCEngine__NeedMoreThanZero();
    error DSCEngine__TokenAddressesAndPriceFeedAddressesMustBeSameLength();
    error DSCEngine__NotAllowedToken();
    error DSCEngine__TransferFailed();
    error DSCEngine__BreaksHealthFactor(uint userHealthFactor);
    error DSCEngine__MintFailed();
    error DSCEngine__HealthFactorOk();

    ///////////////////////////////////////////
    /////       State Varibles     ///////////
    //////////////////////////////////////////
    uint256 private constant ADDITIONAL_FEED_PRECISION = 1e10;
    uint256 private constant PRECISION = 1e18;
    uint256 private constant LIQUIDATION_THRESHOLD = 50; // 200% overcollaterlized
    uint256 private constant LIQUIDATION_PRECISION = 100;
    uint256 private constant MIN_HEALTH_FACTOR = 1e18;
    uint256 private constant LIQUIDATION_BONUS = 10; // this means 10% bonus

    mapping(address token => address priceFeed) private s_priceFeeds; // tokenToPriceFeed
    mapping(address user => mapping(address => uint256 amount))
        private s_collateralDeposited;
    mapping(address user => uint256 amountDscMinted) private s_DSCMinted;
    address[] private s_collateralTokens;

    DecentralizedStableCoin private immutable i_dsc;

    ///////////////////////////////////////////
    ///////       Events           ///////////
    //////////////////////////////////////////
    event CollateralDeposited(
        address indexed user,
        address indexed token,
        uint amount
    );

    event CollateralRedeemed(
        address indexed redeemedFrom,
        address indexed redeemTo,
        address indexed token,
        uint256 amount
    );

    ///////////////////////////////////////////
    //////////        Modifier     ///////////
    //////////////////////////////////////////
    modifier moreThanZero(uint256 amount) {
        if (amount == 0) {
            revert DSCEngine__NeedMoreThanZero();
        }
        _;
    }

    modifier isAllowedToken(address token) {
        if (s_priceFeeds[token] == address(0)) {
            revert DSCEngine__NotAllowedToken();
        }
        _;
    }

    ///////////////////////////////////////////
    //////////        Functions     //////////
    //////////////////////////////////////////
    constructor(
        address[] memory tokenAddresses,
        address[] memory priceFeedAddresses,
        address dscAddress
    ) {
        // USD Price feed
        if (tokenAddresses.length != priceFeedAddresses.length) {
            revert DSCEngine__TokenAddressesAndPriceFeedAddressesMustBeSameLength();
        }
        // The basic idea behind this is that if the Token has price feed for USD pairs like BTC/USD and ETH/USD, those tokens are allowed; otherwise, they are NOT allowed.
        for (uint256 i = 0; i < tokenAddresses.length; i++) {
            s_priceFeeds[tokenAddresses[i]] = priceFeedAddresses[i];
            s_collateralTokens.push(tokenAddresses[i]);
        }
        i_dsc = DecentralizedStableCoin(dscAddress);
    }

    ////////////////////////////////////
    ///  Exteranl Functions     ////////
    ///////////////////////////////////

    /**
     * @notice function to deposit collateral and mint DSC token in one transaction
     * @param tokenCollateral The address of the token to deposit as collateral
     * @param amountColateral The amount of collateral to deposit
     * @param amountDscToMint The amount of decentralized stablecoin to mint
     */
    function depositCollateralAndMintDisc(
        address tokenCollateral,
        uint256 amountColateral,
        uint256 amountDscToMint
    ) external {
        depositCollateral(tokenCollateral, amountColateral);
        mintDsc(amountDscToMint);
    }

    /**
     * @notice Function to depoist collateral to the protocol
     * @param tokenCollateralAddress The address of the token to deposit as collateral
     * @param amountCollateral The amount of collateral to deposit
     * @dev if msg.sender don't have balance then the whole transcation will revert including the updated s_collateralDeposited values.
     */
    function depositCollateral(
        address tokenCollateralAddress,
        uint256 amountCollateral
    )
        public
        moreThanZero(amountCollateral)
        isAllowedToken(tokenCollateralAddress)
        nonReentrant
    {
        s_collateralDeposited[msg.sender][
            tokenCollateralAddress
        ] += amountCollateral;
        emit CollateralDeposited(
            msg.sender,
            tokenCollateralAddress,
            amountCollateral
        );
        bool success = IERC20(tokenCollateralAddress).transferFrom(
            msg.sender,
            address(this),
            amountCollateral
        );
        if (!success) {
            revert DSCEngine__TransferFailed();
        }
    }

    /**
     * @notice This function burn DSC and redeem undelying collateral in one transcation
     * @param tokenCollateralAddress The address of the token to redeem 
     * @param amountCollateral The amount of collateral to redeem
     * @param amountDscToBurn The amount of DSC token to burn
     */
    function redeemCollateralForDsc(address tokenCollateralAddress, uint256 amountCollateral, uint256 amountDscToBurn) external {
        burnDsc(amountDscToBurn);
        redeemCollateral(tokenCollateralAddress, amountCollateral);
        // redeemCollateral already checks health factor
    }

    // in order to redeem collateral
    // 1. Health factor must be over 1 AFTER collateral pulled
    // DRY : Don't Repeat Yourself
    // CEI : Check, Effects, Interactions
    function redeemCollateral(
        address tokenCollateralAddress,
        uint256 amountCollateral
    ) public moreThanZero(amountCollateral) nonReentrant {
       _redeemCollateral(tokenCollateralAddress, amountCollateral, msg.sender,msg.sender);
       _revertIfHealthFactorIsBroken(msg.sender);
    }

    /**
     * @dev The must have more collateral value than the threshold
     * @param amountDscToMint The amount of decentralized stablecoin to mint
     */
    function mintDsc(
        uint amountDscToMint
    ) public moreThanZero(amountDscToMint) nonReentrant {
        s_DSCMinted[msg.sender] += amountDscToMint;
        // revert if they minted too much ($150 DSC, $100 ETH)
        _revertIfHealthFactorIsBroken(msg.sender);
        bool minted = i_dsc.mint(msg.sender, amountDscToMint);
        if (!minted) {
            revert DSCEngine__MintFailed();
        }
    }

    function burnDsc(uint256 amount) public moreThanZero(amount){
        s_DSCMinted[msg.sender] -= amount;
        bool success = i_dsc.transferFrom(msg.sender, address(this), amount);
        if(!success){
            revert DSCEngine__TransferFailed();
        }
        i_dsc.burn(amount);
        _revertIfHealthFactorIsBroken(msg.sender); // I don't think this would ever hit...
    }

    // WE NEED to liquidate positions when undercollateralized
    
    // $100 ETH backing $50 DSC ✅ This will work (our threshold)
    // $20 ETH backing $50 DSC ❌ this will NOT work

    // we need someone to liquidate the position
    // $75 ETH backing $50 DSC (below our threshold)
    // Liquidator takes $75 worth of ETH backing and burns off the $50 DSC

    // If someone is almost undercollaterlized, we will pay you to liquidate them!
    /**
     * @notice You can partially liquidate a user
     * @notice You wil get a liquidate bonus for taking the user funds
     * @dev This function working assumes the protocol will be roughly 200% overcollateralized in order for this to work
     * @notice A known bug would be if the protocol were 100% or less collaterlized, then we wouldn't be able to incentive the liquidators.
     * For example, if the price of the collateral plummeted before anoyine could be liquidated.
     * 
     * @param collateral The address of the token to liquidate from the user
     * @param user address of the user who brokes the health factor
     * @param debtToCover The maount of DSC you want to burn to improve the users health factor
     * @dev User health factor should be below MIN_HEALTH_FACTOR
     */
    function liquidate(address collateral, address user, uint256 debtToCover) external moreThanZero(debtToCover) nonReentrant{
        // need to check health factor of the user
        uint256 startingUserHealthFactor = _healthFactor(user);
        if(startingUserHealthFactor >= MIN_HEALTH_FACTOR){
            revert DSCEngine__HealthFactorOk();
        }
        // we want to burn their DSC "debt" and take their collateral
        // Bad User : $140 ETH, $100 DSC
        // debtToCover = $100
        // $100 of DSC == ?? ETH ?
        // 0.05 ETH
        uint256 tokenAmountFromDebtCovered = getTokenAmountFromUsd(collateral, debtToCover);
        // and give them a 10% bonus
        // So we are giving the liquiadator $110 of weth for 100 DSC
        //! we should implement a feature to liquidate in the event the protcol is insolvent
        // and sweep extra amounts into a treasury

        // 0.05 * 0.1 = 0.005, Getting 0.055
        uint256 bonusCollateral = (tokenAmountFromDebtCovered * LIQUIDATION_BONUS) / LIQUIDATION_BONUS;

        uint256 totalCollateralToRedeem = tokenAmountFromDebtCovered + bonusCollateral;
        _redeemCollateral(collateral,totalCollateralToRedeem, user, msg.sender);
    }

    //////////////////////////////////////////////////
    ///////  Private & Internal Functions     ////////
    //////////////////////////////////////////////////

    /**
     * @dev Low-Level internal function, do not call unless the function calling it is chceking for health factors being broken
     */
    function _burnDsc(uint256 amountDscToBurn, address onBehalfOf, address dscFrom) private {
        s_DSCMinted[onBehalfOf] -= amountDscToBurn;
        bool success = i_dsc.transferFrom(dscFrom, address(this), amountDscToBurn);
        if(!success){
            revert DSCEngine__TransferFailed();
        }
        i_dsc.burn(amountDscToBurn);
    }


    function _redeemCollateral(address tokenCollateralAddress, uint256 amountCollateral, address from, address to) private {
         s_collateralDeposited[from][
            tokenCollateralAddress
        ] -= amountCollateral;
        emit CollateralRedeemed(
            from,
            to,
            tokenCollateralAddress,
            amountCollateral
            
        );
        bool success = IERC20(tokenCollateralAddress).transfer(to, amountCollateral);
        if(!success){
            revert DSCEngine__TransferFailed();
        }
        _revertIfHealthFactorIsBroken(msg.sender);
    }

    function _getAccoutInformation(
        address user
    )
        private
        view
        returns (uint256 totalDscMinted, uint256 collateralValueInUsd)
    {
        totalDscMinted = s_DSCMinted[user];
        collateralValueInUsd = getAccountCollateralValue(user);
    }

    /**
     * @notice Returns how close to liquidate a user is
     * @dev if a user is below 1, then they can get liquidated
     * @param user address of the user
     */
    function _healthFactor(address user) private view returns (uint256) {
        // total DSC minted
        // total collateral VALUE
        (
            uint256 totalDscMinted,
            uint256 collateralValueInUsd
        ) = _getAccoutInformation(user);
        uint256 collateralAdjustedForThreshold = (collateralValueInUsd *
            LIQUIDATION_THRESHOLD) / LIQUIDATION_PRECISION;
        // 1000 ETH / 100 DSC
        // 1000 * 50 = 50,000 / 100 = (500 / 100) > 1

        // $ 150 ETH  / 100 DSC = 1.5
        // 150 * 50 = 7500 / 100 = (75 / 100) < 1
        return (collateralAdjustedForThreshold * PRECISION) / totalDscMinted;
    }

    function _revertIfHealthFactorIsBroken(address user) internal view {
        // 1. check health factor (do they have enough collateral)
        // 2. Revert if they don't have a good health factor
        uint256 userHealthFactor = _healthFactor(user);
        if (userHealthFactor < MIN_HEALTH_FACTOR) {
            revert DSCEngine__BreaksHealthFactor(userHealthFactor);
        }
    }

    

    //////////////////////////////////////////////////////
    ///////  Public & External VIEW Functions     ////////
    //////////////////////////////////////////////////////

    
    function getTokenAmountFromUsd(address token, uint256 usdAmountInWei) public view returns(uint256){
        // price of ETH (token)
        // $2000/ETH = $1000 = 0.5 ETH
        AggregatorV3Interface priceFeed = AggregatorV3Interface(s_priceFeeds[token]);
        (,int256 price,,,) = priceFeed.latestRoundData();
        // ($1000e18 * 1e18) / ($2000e8 * 1e10)
        // 0.5 ETH
        return (usdAmountInWei * PRECISION) / (uint256(price) * ADDITIONAL_FEED_PRECISION);
    }

    function getAccountCollateralValue(
        address user
    ) public view returns (uint256 totalCollateralValueInUsd) {
        // loop through each collateral token, get the amount they have depoisted, and map
        //it to the price, to get the USD Value
        for (uint256 i = 0; i < s_collateralTokens.length; i++) {
            address token = s_collateralTokens[i];
            uint256 amount = s_collateralDeposited[user][token];
            totalCollateralValueInUsd += getUsdValue(token, amount);
        }
        return totalCollateralValueInUsd;
    }

    function getUsdValue(
        address token,
        uint256 amount
    ) public view returns (uint256) {
        AggregatorV3Interface priceFeed = AggregatorV3Interface(
            s_priceFeeds[token]
        );
        (, int256 price, , , ) = priceFeed.latestRoundData();
        // 1 ETH  = $1000
        // the returned value from CL will be 1000 * 1e8
        return
            ((uint256(price) * ADDITIONAL_FEED_PRECISION) * amount) / PRECISION;
    }
}
