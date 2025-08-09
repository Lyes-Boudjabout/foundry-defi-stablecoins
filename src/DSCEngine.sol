// SPDX-License-Identifier: MIT
pragma solidity ^0.8.8;

import {IDSCEngine} from "./interfaces/IDSCEngine.sol";
import {DecentralizedStableCoin} from "../src/DecentralizedStableCoin.sol";
import {ReentrancyGuard} from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {AggregatorV3Interface} from "@chainlink/contracts/src/v0.8/interfaces/AggregatorV3Interface.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

/**
 * @title DSC Engine
 * @author Lyes-Boudjabout
 * This system is designed to be as minimal as possible, and have the tokens maintain a 1 token = 1$ peg
 * This stablecoin has the following properties:
 * - Exogenous Collateral
 * - Dollar Pegged
 * - Algorithmically Stable
 * @notice This contract is the core of the DSC System, it handles all the logic for minting and redeeming DSC, as well as depositing and withdrawing collateral
 * @notice This contract is VERY loosely based on the MakerDAO DSS (DAI) system
 */
contract DSCEngine is IDSCEngine, ReentrancyGuard {
    using SafeERC20 for IERC20;

    /*************  Erros  *************/
    error DSCEngine__CollateralAmountCantBeZero();
    error DSCEngine__TokenAddressesAndPriceFeedAddressesMustBeSameLength();
    error DSCEngine__DscAddressCantBeZero();
    error DSCEngine__TokenAddressNotAllowed();
    error DSCEngine__TransferFailed();

    /*************  State Variables  *************/
    uint256 private constant ADDITIONAL_FEED_PRECISION = 1e10;
    uint256 private constant PRECISION = 1e18;

    mapping(address token => address priceFeed) private s_priceFeeds;
    mapping(address user => mapping(address token => uint256 amount)) private s_collateralDeposited;
    mapping(address user => uint256 dscMinted) private s_userAddressToAmountDscMinted;
    address[] private s_collateralTokens;
    
    /*************  Immutable Variables  *************/
    DecentralizedStableCoin private immutable i_dscAddress;

    /*************  Events  *************/
    event CollateralDeposit(address indexed user, address indexed token, uint256 indexed amount);

    /*************  Modifiers  *************/
    modifier moreThanZero(uint256 amount) {
        if (amount <= 0) {
            revert DSCEngine__CollateralAmountCantBeZero();
        }
        _;
    }

    modifier isAllowedToken(address token) {
        if(s_priceFeeds[token] == address(0)) {
            revert DSCEngine__TokenAddressNotAllowed();
        }
        _;
    }

    /*************  Constructor  *************/
    constructor(
        address[] memory tokenAddresses,
        address[] memory priceFeedsAddresses,
        DecentralizedStableCoin dscAddress
    ) {
        if(tokenAddresses.length != priceFeedsAddresses.length) {
            revert DSCEngine__TokenAddressesAndPriceFeedAddressesMustBeSameLength();
        }
        if(address(dscAddress) == address(0)) {
            revert DSCEngine__DscAddressCantBeZero();
        }
        for (uint i = 0; i < tokenAddresses.length; i++) {
            s_priceFeeds[tokenAddresses[i]] = priceFeedsAddresses[i];
            s_collateralTokens.push(tokenAddresses[i]);
        }
        i_dscAddress = dscAddress;
    }
    
    /*************  Functions  *************/
    function depositCollateralAndMintDsc() external override {}

    /**
     * @param tokenCollateralAddress the address of the token to deposit as collateral
     * @param amountCollateral the amount of collateral to deposit
     */
    function depositCollateral(
        address tokenCollateralAddress,
        uint256 amountCollateral
    ) 
        external 
        override 
        isAllowedToken(tokenCollateralAddress) 
        moreThanZero(amountCollateral)
        nonReentrant
    {
        s_collateralDeposited[msg.sender][tokenCollateralAddress] += amountCollateral;
        IERC20(tokenCollateralAddress).safeTransferFrom(msg.sender, address(this), amountCollateral);
        emit CollateralDeposit(msg.sender, tokenCollateralAddress, amountCollateral);
    }

    /**
     * 
     */
    function redeemCollateralForDsc() external override {}

    /**
     * 
     */
    function redeemCollateral() external override {}

    /**
     * @notice follows CEI (Checks, , Interactions)
     * @param amountDscToMint the amount of decentralized stablecoin to mint
     * @notice they must have more collateral value than the minimum threshold
     */
    function mintDsc(uint256 amountDscToMint) external override moreThanZero(amountDscToMint) nonReentrant {
        s_userAddressToAmountDscMinted[msg.sender] += amountDscToMint;
    }

    /**
     * 
     */
    function burnDsc() external override {}

    /**
     * 
     */
    function liquidate() external override {}

    /**
     * 
     */
    function getHealthFactor() external view override {}

    /**
     * @param account dfdb
     * @return totalDscMinted bdb
     * @return collateralValueInUsd dfbdbf
     */
    function _getAccountInformation(address account) private view returns(uint256 totalDscMinted, uint256 collateralValueInUsd) {
        totalDscMinted = s_userAddressToAmountDscMinted[account];
        collateralValueInUsd = getAccountCollateralValue(account);
    }

    /**
     * @param user gsxk
     */
    function _healthFactor(address user) private view returns(uint256) {

    }

    /**
     * @param user df
     */
    function _revertIfHealthFactorIsBroken(address user) internal view {}

    /*************  Getter Functions  *************/
    function getPriceFeedByToken(address token) public view returns(address) {
        return s_priceFeeds[token];
    }

    function getDscAddress() public view returns(DecentralizedStableCoin) {
        return i_dscAddress;
    }

    function getAccountCollateralValue(address user) public view returns(uint256 totalCollateralInUsd) {
        for (uint i = 0; i < s_collateralTokens.length; i++) {
            address token = s_collateralTokens[i];
            uint256 amount = s_collateralDeposited[user][token];
            totalCollateralInUsd += getUsdValue(token, amount);
        }
    }

    function getUsdValue(address token, uint256 amount) public view returns(uint256) {
        AggregatorV3Interface priceFeed = AggregatorV3Interface(s_priceFeeds[token]);
        (, int256 price,,,) = priceFeed.latestRoundData();
        return ((uint256(price) * ADDITIONAL_FEED_PRECISION) * amount) / PRECISION;
    }
}
