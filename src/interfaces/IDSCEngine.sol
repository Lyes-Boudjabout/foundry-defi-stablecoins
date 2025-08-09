// SPDX-License-Identifier: SEE LICENSE IN LICENSE
pragma solidity ^0.8.8;

interface IDSCEngine {
    function depositCollateralAndMintDsc() external;

    /**
     * @dev Deposits an amount of collateral on behalf of a token by providing its address
     * @param tokenCollateralAddress the address of the token to deposit as collateral
     * @param amountCollateral the amount of collateral to deposit
     */
    function depositCollateral(
        address tokenCollateralAddress,
        uint256 amountCollateral
    ) external;

    function redeemCollateralForDsc() external;

    function redeemCollateral() external;

    function mintDsc(uint256 amountDscToMint) external;

    function burnDsc() external;

    function liquidate() external;

    function getHealthFactor() external view;
}
