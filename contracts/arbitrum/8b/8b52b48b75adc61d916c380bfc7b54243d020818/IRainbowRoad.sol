// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.19;

import {IArc} from "./IArc.sol";

interface IRainbowRoad {
    
    function acceptTeam() external;
    function actionHandlers(string calldata action) external view returns (address);
    function arc() external view returns (IArc);
    function blockToken(address tokenAddress) external;
    function disableFeeManager(address feeManager) external;
    function disableOpenTokenWhitelisting() external;
    function disableReceiver(address receiver) external;
    function disableSender(address sender) external;
    function disableSendFeeBurn() external;
    function disableSendFeeCharge() external;
    function disableWhitelistingFeeBurn() external;
    function disableWhitelistingFeeCharge() external;
    function enableFeeManager(address feeManager) external;
    function enableOpenTokenWhitelisting() external;
    function enableReceiver(address receiver) external;
    function enableSendFeeBurn() external;
    function enableSender(address sender) external;
    function enableSendFeeCharge() external;
    function enableWhitelistingFeeBurn() external;
    function enableWhitelistingFeeCharge() external;
    function sendFee() external view returns (uint256);
    function whitelistingFee() external view returns (uint256);
    function chargeSendFee() external view returns (bool);
    function chargeWhitelistingFee() external view returns (bool);
    function burnSendFee() external view returns (bool);
    function burnWhitelistingFee() external view returns (bool);
    function openTokenWhitelisting() external view returns (bool);
    function config(string calldata configName) external view returns (bytes memory);
    function blockedTokens(address tokenAddress) external view returns (bool);
    function feeManagers(address feeManager) external view returns (bool);
    function receiveAction(string calldata action, address to, bytes calldata payload) external;
    function sendAction(string calldata action, address from, bytes calldata payload) external;
    function setActionHandler(string memory action, address handler) external;
    function setArc(address _arc) external;
    function setSendFee(uint256 _fee) external;
    function setTeam(address _team) external;
    function setTeamRate(uint256 _teamRate) external;
    function setToken(string calldata tokenSymbol, address tokenAddress) external;
    function setWhitelistingFee(uint256 _fee) external;
    function team() external view returns (address);
    function teamRate() external view returns (uint256);
    function tokens(string calldata tokenSymbol) external view returns (address);
    function MAX_TEAM_RATE() external view returns (uint256);
    function receivers(address receiver) external view returns (bool);
    function senders(address sender) external view returns (bool);
    function unblockToken(address tokenAddress) external;
    function whitelist(address tokenAddress) external;
}
