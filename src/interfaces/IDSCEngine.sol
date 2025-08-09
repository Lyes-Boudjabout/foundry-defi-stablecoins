// SPDX-License-Identifier: SEE LICENSE IN LICENSE
pragma solidity ^0.8.8;

interface IDSCEngine {
    function depositCollateralAndMintDsc(address token, uint256 amountCollateral, uint256 amountToMint) external;

    /**
     * @dev Deposits an amount of collateral on behalf of a token by providing its address
     * @param tokenCollateralAddress the address of the token to deposit as collateral
     * @param amountCollateral the amount of collateral to deposit
     */
    function depositCollateral(address tokenCollateralAddress, uint256 amountCollateral) external;

    function redeemCollateralForDsc(address, uint256, uint256) external;

    function redeemCollateral(address, uint256) external;

    function mintDsc(uint256 amountDscToMint) external;

    function burnDsc(uint256 burnAmount) external;

    function liquidate(address token, address user, uint256 debtToCover) external;

    function getHealthFactor(address user) external view returns(uint256);
}
