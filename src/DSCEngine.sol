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

    /**
     *  Errors
     */
    error DSCEngine__CollateralAmountCantBeZero();
    error DSCEngine__MintAmountCantBeZero();
    error DSCEngine__BurnAmountCantBeZero();
    error DSCEngine__RedeemAmountCantBeZero();
    error DSCEngine__TokenAddressesAndPriceFeedAddressesMustBeSameLength();
    error DSCEngine__DscAddressCantBeZero();
    error DSCEngine__TokenAddressNotAllowed(address token);
    error DSCEngine__TransferFailed();
    error DSCEngine__MintFailed();
    error DSCEngine__HealthFactorOk();
    error DSCEngine__HealthFactorNotImproved();
    error DSCEngine__BreaksHealthFactor(uint256 healthFactor);

    /**
     *  State Variables
     */
    uint256 private constant ADDITIONAL_FEED_PRECISION = 1e10;
    uint256 private constant PRECISION = 1e18;
    uint256 private constant LIQUIDATION_THRESHOLD = 50; //200% overcollateralized
    uint256 private constant LIQUIDATION_PRECISION = 100;
    uint256 private constant HEALTH_FACTOR_THRESHOLD = 100;

    mapping(address token => address priceFeed) private s_priceFeeds;
    mapping(address user => mapping(address token => uint256 amount)) private s_collateralDeposited;
    mapping(address user => uint256 dscMinted) private s_userAddressToAmountDscMinted;
    address[] private s_collateralTokens;

    /**
     *  Immutable Variables
     */
    DecentralizedStableCoin private immutable i_dscAddress;

    /**
     *  Events
     */
    event CollateralDeposit(address indexed user, address indexed token, uint256 indexed amount);

    /**
     *  Modifiers
     */
    modifier moreThanZero(uint256 amount) {
        if (amount <= 0) {
            revert DSCEngine__CollateralAmountCantBeZero();
        }
        _;
    }

    modifier isAllowedToken(address token) {
        if (s_priceFeeds[token] == address(0)) {
            revert DSCEngine__TokenAddressNotAllowed(token);
        }
        _;
    }

    /**
     *  Constructor
     */
    constructor(
        address[] memory tokenAddresses,
        address[] memory priceFeedsAddresses,
        DecentralizedStableCoin dscAddress
    ) {
        if (tokenAddresses.length != priceFeedsAddresses.length) {
            revert DSCEngine__TokenAddressesAndPriceFeedAddressesMustBeSameLength();
        }
        if (address(dscAddress) == address(0)) {
            revert DSCEngine__DscAddressCantBeZero();
        }
        for (uint256 i = 0; i < tokenAddresses.length; i++) {
            s_priceFeeds[tokenAddresses[i]] = priceFeedsAddresses[i];
            s_collateralTokens.push(tokenAddresses[i]);
        }
        i_dscAddress = dscAddress;
    }

    /**
     *  Functions
     */
    function depositCollateralAndMintDsc(address token, uint256 amountCollateral, uint256 amountToMint) external override {}

    /**
     * @param tokenCollateralAddress the address of the token to deposit as collateral
     * @param amountCollateral the amount of collateral to deposit
     */
    function depositCollateral(address tokenCollateralAddress, uint256 amountCollateral)
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
    function redeemCollateralForDsc(address, uint256, uint256) external override {}

    /**
     *
     */
    function redeemCollateral(address, uint256) external override {}

    /**
     * @notice follows CEI (Checks, , Interactions)
     * @param amountDscToMint the amount of decentralized stablecoin to mint
     * @notice they must have more collateral value than the minimum threshold
     */
    function mintDsc(uint256 amountDscToMint) external override moreThanZero(amountDscToMint) nonReentrant {
        s_userAddressToAmountDscMinted[msg.sender] += amountDscToMint;
        _revertIfHealthFactorIsBroken(msg.sender);
        bool minted = i_dscAddress.mint(msg.sender, amountDscToMint);
        if (!minted) {
            revert DSCEngine__MintFailed();
        }
    }

    /**
     *
     */
    function burnDsc(uint256 burnAmount) external override {}

    /**
     *
     */
    function liquidate(address token, address user, uint256 debtToCover) external override {}

    /**
     *
     */
    function getHealthFactor(address user) external view override returns(uint256) {
        return _healthFactor(user);
    }

    /**
     * @param account user's address
     * @return totalDscMinted total amount of minted DSC
     * @return collateralValueInUsd the value in USD
     */
    function getAccountInformation(address account)
        public
        view
        returns (uint256 totalDscMinted, uint256 collateralValueInUsd)
    {
        totalDscMinted = s_userAddressToAmountDscMinted[account];
        collateralValueInUsd = getAccountCollateralValue(account);
    }

    function calculateHealthFactor(uint256 amountToMint, uint256 usdValue) public view returns(uint256) {

    }

    /**
     * @param user the user's address
     * returns how close to liquidate a user is, if a user goes below 1, then they can get liquidated
     */
    function _healthFactor(address user) private view returns (uint256) {
        (uint256 totalDscMinted, uint256 collateralValueInUsd) = getAccountInformation(user);
        uint256 collateralAdjustedForThreshold = (collateralValueInUsd * LIQUIDATION_THRESHOLD) / LIQUIDATION_PRECISION;
        return (collateralAdjustedForThreshold * PRECISION) / totalDscMinted;
    }

    /**
     * @param user the address of the user for which we are checking health factor
     */
    function _revertIfHealthFactorIsBroken(address user) internal view {
        uint256 userHealthFactor = _healthFactor(user);
        if (userHealthFactor < HEALTH_FACTOR_THRESHOLD) {
            revert DSCEngine__BreaksHealthFactor(userHealthFactor);
        }
    }

    /**
     *  Getter Functions
     */
    function getPriceFeedByToken(address token) public view returns (address) {
        return s_priceFeeds[token];
    }

    function getDscAddress() public view returns (DecentralizedStableCoin) {
        return i_dscAddress;
    }

    function getAccountCollateralValue(address user) public view returns (uint256 totalCollateralInUsd) {
        for (uint256 i = 0; i < s_collateralTokens.length; i++) {
            address token = s_collateralTokens[i];
            uint256 amount = s_collateralDeposited[user][token];
            totalCollateralInUsd += getUsdValue(token, amount);
        }
    }

    function getUsdValue(address token, uint256 amount) public view returns (uint256) {
        AggregatorV3Interface priceFeed = AggregatorV3Interface(s_priceFeeds[token]);
        (, int256 price,,,) = priceFeed.latestRoundData();
        return ((uint256(price) * ADDITIONAL_FEED_PRECISION) * amount) / PRECISION;
    }

    function getAdditionalFeedPrecision() public pure returns(uint256) {
        return ADDITIONAL_FEED_PRECISION;
    }
    
    function getPrecision() public pure returns(uint256) {
        return PRECISION;
    }

    function getDsc() public view returns(address) {
        return address(i_dscAddress);
    }

    function getLiquidationBonus() public view returns(uint256) {

    }
    
    function getLiquidationPrecision() public pure returns(uint256) {
        return LIQUIDATION_PRECISION;
    }
    
    function getLiquidationThreshold() public pure returns(uint256) {
        return LIQUIDATION_THRESHOLD;
    }

    function getCollateralBalanceOfUser(address token, address user) public view returns(uint256) {

    }

    function getTokenAmountFromUsd(address token, uint256 amount) public view returns(uint256) {

    }

    function getCollateralTokens() public view returns(address[] memory) {

    }

    function getMinHealthFactor() public pure returns(uint256) {
        return HEALTH_FACTOR_THRESHOLD;
    }

    function getCollateralTokenPriceFeed(address token) public view returns(address) {

    }
}
