// SPDX-License-Identifier: MIT
pragma solidity 0.8.18;
import {DecentralizedStableCoin} from "./DecentralizedStableCoin.sol";
import {ReentrancyGuard} from "@openzeppelin/contracts/security/ReentrancyGuard.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

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

    ///////////////////////////////////////////
    /////       State Varibles     ///////////
    //////////////////////////////////////////
    mapping(address token => address priceFeed) private s_priceFeeds; // tokenToPriceFeed
    mapping(address user => mapping(address => uint256 amount)) private s_collateralDeposited;
    mapping(address user => uint256 amountDscMinted) private s_DSCMinted;
    address[] private s_collateralTokens;
    

    DecentralizedStableCoin private immutable i_dsc;

    ///////////////////////////////////////////
    ///////       Events           ///////////
    //////////////////////////////////////////
    event CollateralDeposited(address indexed user, address indexed token, uint amount);

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

    function depositCollateralAndMintDisc() external {}

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
        external
        moreThanZero(amountCollateral)
        isAllowedToken(tokenCollateralAddress)
        nonReentrant
    {
        s_collateralDeposited[msg.sender][tokenCollateralAddress] += amountCollateral;
        emit CollateralDeposited(msg.sender, tokenCollateralAddress, amountCollateral);
        bool success = IERC20(tokenCollateralAddress).transferFrom(msg.sender, address(this), amountCollateral);
        if (!success){
            revert DSCEngine__TransferFailed();
        }
    }

    /**
     * @dev The must have more collateral value than the threshold
     * @param amountDscToMint The amount of decentralized stablecoin to mint
     */
    function mintDsc(uint amountDscToMint) external moreThanZero(amountDscToMint) ReentrancyGuard {
        s_DSCMinted[msg.sender] += amountDscMinted;
        // revert if they minted too much ($150 DSC, $100 ETH)
        revertIfHealthFactorIsBroken(msg.sender);
    }

    //////////////////////////////////////////////////
    ///////  Private & Internal Functions     ////////
    //////////////////////////////////////////////////

    function _getAccoutInformation(address user) private view returns(uint256 totalDscMinted, uint256 collateralValueInUsd) {
        totalDscMinted = s_DSCMinted[user];
        collateralValueInUsd = getAccountCollateralValue(user);
    }

    /**
     * @notice Returns how close to liquidate a user is
     * @dev if a user is below 1, then they can get liquidated
     * @param user address of the user
     */
    function _healthFactor(address user) private view returns(uint256) {
        // total DSC minted
        // total collateral VALUE
        (uint256 totalDscMinted, uint256 collateralValueInUsd) = _getAccoutInformation(user);
    }

    function _revertIfHealthFactorIsBroken(address user) internal view {
        // 1. check health factor (do they have enough collateral)
        // 2. Revert if they don't have a good health factor
    }

    //////////////////////////////////////////////////////
    ///////  Public & External view Functions     ////////
    //////////////////////////////////////////////////////

    function getAccountCollateralValue(address user) public view returns(uint256){
        // loop through each collateral token, get the amount they have depoisted, and map 
        //it to the price, to get the USD Value
        for(uint256 i=0; i< s_collateralTokens.length; i++){
            address token = s_collateralTokens[i];
            uint256 amount = s_collateralDeposited[user][token];
            totalCollateralValueInUsd +=
        }
    }

    function getUsdValue(address token, uint256 amount) public view returns(uint256){
        
    }

}
