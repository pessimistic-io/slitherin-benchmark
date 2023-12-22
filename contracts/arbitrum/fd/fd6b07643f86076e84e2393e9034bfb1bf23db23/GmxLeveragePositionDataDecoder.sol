// SPDX-License-Identifier: GPL-3.0

pragma solidity 0.7.6;

/// @title GmxLeveragePositionDataDecoder Contract
/// @author Alfred Team <security@alfred.capital>
/// @notice Abstract contract containing data decodings for GmxLeveragePositions payloads
abstract contract GmxLeveragePositionDataDecoder {
    /// @dev Helper to decode args used during the AddLiquidity action
    function __decodeCreateIncreasePositionActionArgs(
        bytes memory _actionArgs
    )
        internal
        pure
        returns (
            address[] memory _path,
            address _indexToken,
            uint256 _minOut,
            uint256 _amount,
            uint256 _sizeDelta,
            bool _isLong,
            uint256 _acceptablePrice,
            uint256 _executionFee,
            bytes32 _referralCode,
            address _callbackTarget
        )
    {
        return
            abi.decode(
                _actionArgs,
                (
                    address[],
                    address,
                    uint256,
                    uint256,
                    uint256,
                    bool,
                    uint256,
                    uint256,
                    bytes32,
                    address
                )
            );
    }

    function __decodeCreateDecreaseActionArgs(
        bytes memory _actionArgs
    )
        internal
        pure
        returns (
            address[] memory _path,
            address _indexToken,
            uint256 _collateralDelta,
            uint256 _sizeDelta,
            bool _isLong,
            uint256 _acceptablePrice,
            uint256 _minOut,
            uint256 _executionFee,
            bool _withdrawETH
        )
    {
        return
            abi.decode(
                _actionArgs,
                (address[], address, uint256, uint256, bool, uint256, uint256, uint256, bool)
            );
    }
}

