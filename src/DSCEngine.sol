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
     *  Errors  *
     */
    error DSCEngine__NeedToBeMoreThanZero();
    error DSCEngine__TokenAddressesAndPriceFeedAddressesMustBeSameLength();
    error DSCEngine__DscAddressCantBeZero();
    error DSCEngine__TokenAddressNotAllowed(address token);
    error DSCEngine__TransferFailed();
    error DSCEngine__MintFailed();
    error DSCEngine__HealthFactorOk();
    error DSCEngine__HealthFactorNotImproved();
    error DSCEngine__BreaksHealthFactor(uint256 healthFactor);

    /**
     *  State Variables  *
     */
    uint256 private constant ADDITIONAL_FEED_PRECISION = 1e10;
    uint256 private constant PRECISION = 1e18;
    uint256 private constant LIQUIDATION_THRESHOLD = 50; //200% overcollateralized
    uint256 private constant LIQUIDATION_PRECISION = 100;
    uint256 private constant LIQUIDATION_BONUS = 10;
    uint256 private constant HEALTH_FACTOR_THRESHOLD = 100;

    mapping(address token => address priceFeed) private s_priceFeeds;
    mapping(address user => mapping(address token => uint256 amount)) private s_collateralDeposited;
    mapping(address user => uint256 dscMinted) private s_userAddressToAmountDscMinted;
    address[] private s_collateralTokens;

    /**
     *  Immutable Variables  *
     */
    DecentralizedStableCoin private immutable i_dscAddress;

    /**
     *  Events  *
     */
    event CollateralDeposit(address indexed user, address indexed token, uint256 indexed amount);
    event CollateralRedeemed(
        address indexed redeemedFrom,
        address indexed redeemedTo,
        address indexed tokenCollateralAddress,
        uint256 amountCollateral
    );

    /**
     *  Modifiers  *
     */
    modifier moreThanZero(uint256 amount) {
        if (amount <= 0) {
            revert DSCEngine__NeedToBeMoreThanZero();
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
     *  Constructor  *
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
     *  Functions  *
     */

    /**
     * @param tokenCollateralAddress the address of the token provided as collateral
     * @param amountCollateral the amount of collateral to deposit
     * @param amountDscToMint the amount of DSC to mint depending on collateral
     * @notice this function will deposit your collateral and mint you DSC in one transaction
     */
    function depositCollateralAndMintDsc(
        address tokenCollateralAddress,
        uint256 amountCollateral,
        uint256 amountDscToMint
    ) external override {
        depositCollateral(tokenCollateralAddress, amountCollateral);
        mintDsc(amountDscToMint);
    }

    /**
     * @param tokenCollateralAddress the address of the token to deposit as collateral
     * @param amountCollateral the amount of collateral to deposit
     */
    function depositCollateral(address tokenCollateralAddress, uint256 amountCollateral)
        public
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
     * @param tokenCollateralAddress the address of the token to deposit as collateral
     * @param amountCollateral the amount of collateral to deposit
     * @param amoutnDscToBurn the amount of DSC to be burnt
     */
    function redeemCollateralForDsc(address tokenCollateralAddress, uint256 amountCollateral, uint256 amoutnDscToBurn)
        external
        override
    {
        burnDsc(amoutnDscToBurn);
        redeemCollateral(tokenCollateralAddress, amountCollateral);
    }

    /**
     * @param tokenCollateralAddress the address of the token to deposit as collateral
     * @param amountCollateral the amount of collateral to deposit
     */
    function redeemCollateral(address tokenCollateralAddress, uint256 amountCollateral)
        public
        override
        moreThanZero(amountCollateral)
        isAllowedToken(tokenCollateralAddress)
        nonReentrant
    {
        _redeemCollateral(msg.sender, msg.sender, tokenCollateralAddress, amountCollateral);
        _revertIfHealthFactorIsBroken(msg.sender);
    }

    /**
     * @notice follows CEI (Checks, Effects, Interactions)
     * @param amountDscToMint the amount of decentralized stablecoin to mint
     * @notice they must have more collateral value than the minimum threshold
     */
    function mintDsc(uint256 amountDscToMint) public override moreThanZero(amountDscToMint) nonReentrant {
        s_userAddressToAmountDscMinted[msg.sender] += amountDscToMint;
        _revertIfHealthFactorIsBroken(msg.sender);
        bool minted = i_dscAddress.mint(msg.sender, amountDscToMint);
        if (!minted) {
            revert DSCEngine__MintFailed();
        }
    }

    /**
     * @param burnAmount the amount of DSC to be burnt
     */
    function burnDsc(uint256 burnAmount) public override moreThanZero(burnAmount) {
        _burnDsc(burnAmount, msg.sender, msg.sender);
        _revertIfHealthFactorIsBroken(msg.sender);
    }

    /**
     * @param collateralAddress The ERC20 collateral address to liquidate from the user
     * @param user The address of the user who has broken the health factor
     * @param debtToCover The amount of DSC you want to burn to improve the users health factor
     * @notice follows CEI (Checks, Effects, Interactions)
     * @notice you partially liquidate a user
     * @notice you will get a liquidation bonus for taking the users funds
     * @notice this function working assumes the protocol will be roughly 200% overcollateralized in order for this to work
     */
    function liquidate(address collateralAddress, address user, uint256 debtToCover)
        external
        override
        moreThanZero(debtToCover)
        nonReentrant
    {
        uint256 startingUserHealthFactor = _healthFactor(user);
        if (startingUserHealthFactor >= LIQUIDATION_THRESHOLD) {
            revert DSCEngine__HealthFactorOk();
        }
        uint256 tokenAmountFromDebtCovered = getTokenAmountFromUsd(collateralAddress, debtToCover);
        uint256 bonusCollateral = (tokenAmountFromDebtCovered * LIQUIDATION_BONUS) / LIQUIDATION_PRECISION;
        uint256 totalCollateralToRedeem = tokenAmountFromDebtCovered + bonusCollateral;
        _redeemCollateral(user, msg.sender, collateralAddress, totalCollateralToRedeem);
        _burnDsc(debtToCover, user, msg.sender);

        uint256 endingUserHealthFactor = _healthFactor(user);
        if (endingUserHealthFactor <= startingUserHealthFactor) {
            revert DSCEngine__HealthFactorNotImproved();
        }
    }

    /**
     * @param user the address of the user
     */
    function getHealthFactor(address user) external view override returns (uint256) {
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

    /**
     * @param amountToMint amount of DSC to mint
     * @param usdValue the value is US Dollar
     */
    function calculateHealthFactor(uint256 amountToMint, uint256 usdValue) public view returns (uint256) {}

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
     * @param tokenCollateralAddress the address of the token to deposit as collateral
     * @param amountCollateral the amount of collateral to deposit
     * @param _from the address of the sender
     * @param _to  the address of the receiver
     */
    function _redeemCollateral(address _from, address _to, address tokenCollateralAddress, uint256 amountCollateral)
        internal
    {
        s_collateralDeposited[_from][tokenCollateralAddress] -= amountCollateral;
        emit CollateralRedeemed(_from, _to, tokenCollateralAddress, amountCollateral);
        IERC20(tokenCollateralAddress).safeTransfer(_from, amountCollateral);
    }

    /**
     * @param _amountDscToBurn the amount of DSC to be burnt
     * @param _onBehalfOf the address of the one from whome we are removing DSC
     * @param _dscFrom the address of the one who's transfering to the protocol
     * @dev Low-Level internal function, do not call unless the function calling it is checking for health factor being broken
     */
    function _burnDsc(uint256 _amountDscToBurn, address _onBehalfOf, address _dscFrom) private {
        s_userAddressToAmountDscMinted[_onBehalfOf] -= _amountDscToBurn;
        bool success = i_dscAddress.transferFrom(_dscFrom, address(this), _amountDscToBurn);
        if (!success) {
            revert DSCEngine__TransferFailed();
        }
        i_dscAddress.burn(_amountDscToBurn);
    }

    /**
     *  Getter Functions  *
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

    function getAdditionalFeedPrecision() public pure returns (uint256) {
        return ADDITIONAL_FEED_PRECISION;
    }

    function getPrecision() public pure returns (uint256) {
        return PRECISION;
    }

    function getDsc() public view returns (address) {
        return address(i_dscAddress);
    }

    function getLiquidationBonus() public pure returns (uint256) {
        return LIQUIDATION_BONUS;
    }

    function getLiquidationPrecision() public pure returns (uint256) {
        return LIQUIDATION_PRECISION;
    }

    function getLiquidationThreshold() public pure returns (uint256) {
        return LIQUIDATION_THRESHOLD;
    }

    function getCollateralBalanceOfUser(address token, address user) public view returns (uint256) {
        return s_collateralDeposited[token][user];
    }

    function getTokenAmountFromUsd(address token, uint256 usdAmountInWei) public view returns (uint256) {
        AggregatorV3Interface priceFeed = AggregatorV3Interface(s_priceFeeds[token]);
        (, int256 price,,,) = priceFeed.latestRoundData();
        return (usdAmountInWei * PRECISION) / (uint256(price) * ADDITIONAL_FEED_PRECISION);
    }

    function getCollateralTokens() public view returns (address[] memory) {
        return s_collateralTokens;
    }

    function getMinHealthFactor() public pure returns (uint256) {
        return HEALTH_FACTOR_THRESHOLD;
    }

    function getCollateralTokenPriceFeed(address token) public view returns (address) {
        return s_priceFeeds[token];
    }
}
