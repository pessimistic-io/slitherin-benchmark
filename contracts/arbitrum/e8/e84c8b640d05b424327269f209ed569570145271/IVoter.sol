// SPDX-License-Identifier: MIT
pragma solidity ^0.8.18;

interface IVoter {
    function _ve() external view returns (address);

    function governor() external view returns (address);

    function weights(address) external view returns (uint256);

    function emergencyCouncil() external view returns (address);

    function attachTokenToGauge(uint _tokenId, address account) external;

    function detachTokenFromGauge(uint _tokenId, address account) external;

    function emitDeposit(uint _tokenId, address account, uint amount) external;

    function emitWithdraw(uint _tokenId, address account, uint amount) external;

    function isWhitelisted(address token) external view returns (bool);

    function notifyRewardAmount(uint amount) external;

    function distribute(address _gauge) external;

    function gauges(address pool) external view returns (address);

    function feeDistributers(address gauge) external view returns (address);

    function vote(
        uint256 tokenId,
        address[] calldata _poolVote,
        uint256[] calldata _weights
    ) external;

    function reset(uint256 _tokenId) external;
    
    function claimFees(
        address[] memory _fees,
        address[][] memory _tokens,
        uint256 _tokenId
    ) external;
}

