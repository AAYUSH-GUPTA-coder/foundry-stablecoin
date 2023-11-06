// SPDX-License-Identifier: MIT
pragma solidity 0.8.18;
import {DecentralizedStableCoin} from "./DecentralizedStableCoin.sol";

/**
 * @title DSCEngine
 * @author Patrick Collins
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
contract DSCEngine {
    ///////////////////////////////////////////
    //////////        Erros     //////////////
    //////////////////////////////////////////
    error DSCEngine__NeedMoreThanZero();
    error DSCEngine__TokenAddressesAndPriceFeedAddressesMustBeSameLength();

    ///////////////////////////////////////////
    /////       State Varibles     ///////////
    //////////////////////////////////////////
    mapping(address token => address priceFeed) private s_priceFeeds; // tokenToPriceFeed

    DecentralizedStableCoin private i_dsc;

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
        }
    }

    ////////////////////////////////////
    ///  Exteranl Functions     ////////
    ///////////////////////////////////

    function depositCollateralAndMintDisc() external {}

    /**
     * @notice Function to depoist collateral to the protocol
     * @param tokenCollateralAddress The address of the token to deposit as collateral
     * @param amountCollateral The amount of collateral to deposit
     */
    function depositCollateral(
        address tokenCollateralAddress,
        uint256 amountCollateral
    ) external moreThanZero(amountCollateral) {}
}
