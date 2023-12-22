// SPDX-License-Identifier: MIT
pragma solidity 0.8.17;

import "./IRewardHandler.sol";
import "./ITokenTransferProxy.sol";
import "./ILPToken.sol";

interface IDaoMain {
    function setTokenTransferProxy(ITokenTransferProxy) external;
    function setRewardHandler1(IRewardHandler) external;
    function setRewardHandler2(IRewardHandler) external;
    function stakeDaoToken(address, uint256) external;
    function unstakeDaoToken(address, uint256) external;
    function unstakeAllTokens(address) external;
    function returnAllStakedTokensAsAdmin(address, address) external;
}

