// SPDX-License-Identifier: BUSL-1.1

pragma solidity 0.7.6;

import "./IRewardsRecipient.sol";

interface IFutureWallet is IRewardsRecipient {
    /* Events */
    event YieldRedeemed(address indexed _user, uint256 _periodIndex);
    event WithdrawalsPauseChanged(bool _withdrawalPaused);

    /**
     * @notice register the yield of an expired period
     * @param _amount the amount of yield to be registered
     */
    function registerExpiredFuture(uint256 _amount) external;

    /**
     * @notice redeem the yield of the underlying yield of the FYT held by the sender
     * @param _periodIndex the index of the period to redeem the yield from
     */
    function redeemYield(uint256 _periodIndex) external;

    /**
     * @notice return the yield that could be redeemed by an address for a particular period
     * @param _periodIndex the index of the corresponding period
     * @param _user the FYT holder
     * @return the yield that could be redeemed by the token holder for this period
     */
    function getRedeemableYield(uint256 _periodIndex, address _user)
        external
        view
        returns (uint256);

    /**
     * @notice getter for the address of the future corresponding to this future wallet
     * @return the address of the future
     */
    function getFutureAddress() external view returns (address);

    /**
     * @notice getter for the address of the IBT corresponding to this future wallet
     * @return the address of the IBT
     */
    function getIBTAddress() external view returns (address);
}

