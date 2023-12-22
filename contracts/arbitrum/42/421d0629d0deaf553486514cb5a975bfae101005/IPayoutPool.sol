// SPDX-License-Identifier: GPL-3.0-or-later

pragma solidity ^0.8.13;

interface IPayoutPool {
    function CLAIM_PERIOD() external view returns (uint256);

    function SCALE() external view returns (uint256);

    function claim(
        address _user,
        address _crToken,
        uint256 _poolId,
        uint256 _generation
    ) external returns (uint256 claimed, uint256 newGenerationCRAmount);

    function crFactory() external view returns (address);

    function newPayout(
        uint256 _poolId,
        uint256 _generation,
        uint256 _amount,
        uint256 _ratio,
        address _poolAddress
    ) external;

    function payoutCounter() external view returns (uint256);

    function payouts(uint256)
        external
        view
        returns (
            uint256 amount,
            uint256 remaining,
            uint256 endTiemstamp,
            uint256 ratio,
            address priorityPoolAddress
        );

    function policyCenter() external view returns (address);
}

