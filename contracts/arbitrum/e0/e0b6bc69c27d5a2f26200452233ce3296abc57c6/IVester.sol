// SPDX-License-Identifier: MIT
import "./IERC20Upgradeable.sol";

pragma solidity 0.8.17;

interface IVester is IERC20Upgradeable {
    function claimForAccount(address _account, address _receiver)
        external
        returns (uint256);

    function claimable(address _account) external view returns (uint256);

    function depositForAccount(address _account, uint256 _amount) external;

    function withdraw() external;

    function withdrawFor(address account, address _receiver) external;

    function cumulativeClaimAmounts(address _account)
        external
        view
        returns (uint256);

    function claimedAmounts(address _account) external view returns (uint256);

    function pairAmounts(address _account) external view returns (uint256);

    function getVestedAmount(address _account) external view returns (uint256);

    function getMaxVestableAmount(address _account)
        external
        view
        returns (uint256);

    function getTotalVested(address _account) external view returns (uint256);

    function getCombinedAverageStakedAmount(address _account)
        external
        view
        returns (uint256);

    function getPairAmount(address _account, uint256 _esAmount)
        external
        view
        returns (uint256);

    function setHandler(address _handler, bool _isActive) external;
}

