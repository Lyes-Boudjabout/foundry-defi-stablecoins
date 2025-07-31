// SPDX-License-Identifier: SEE LICENSE IN LICENSE
pragma solidity ^0.8.8;

interface IDSCEngine {
    function depositCollateralAndMintDsc() external;

    function redeemCollateralForDsc() external;

    function burnDsc() external;

    function liquidate() external;

    function getHealthFactor() external view;
}
