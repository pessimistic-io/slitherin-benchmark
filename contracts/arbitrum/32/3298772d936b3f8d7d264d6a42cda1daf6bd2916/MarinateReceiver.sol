// SPDX-License-Identifier: GNU GPLv3
pragma solidity ^0.8.4;

import { AccessControl } from "./AccessControl.sol";
import { IERC20 } from "./IERC20.sol";
import { SafeERC20 } from "./SafeERC20.sol";
import { ReentrancyGuard } from "./ReentrancyGuard.sol";


interface IMarinate {
    function addReward(address token, uint256 amount) external;
}

contract MarinateReceiver is AccessControl, ReentrancyGuard {
    using SafeERC20 for IERC20;

    address public immutable UMAMI;
    IMarinate public marinateContract;
    address[] public distributedTokens;
    mapping(address => bool) public isDistributedToken;
    bytes32 public constant ADMIN_ROLE = keccak256("ADMIN_ROLE");
    bytes32 public constant AUTOMATION_ROLE = keccak256("AUTOMATION_ROLE");
    event RewardAdded(address token, uint256 amount);

    constructor(address _marinate, address _UMAMI) {
        UMAMI = _UMAMI;
        marinateContract = IMarinate(_marinate);
        _setupRole(DEFAULT_ADMIN_ROLE, msg.sender);
        _setupRole(ADMIN_ROLE, msg.sender);
    }

    function sendBalancesAsRewards() external onlyAdminOrAutomation nonReentrant {
        for (uint256 i = 0; i < distributedTokens.length; i++) {
            address token = distributedTokens[i];
            uint256 tokenBalance = IERC20(token).balanceOf(address(this));
            if (tokenBalance == 0) { continue; }
            _addRewards(token, tokenBalance);
            emit RewardAdded(token, tokenBalance);
        }
    }

    function _addRewards(address token, uint256 amount) private onlyAdmin {
        IERC20(token).safeApprove(address(marinateContract), amount);
        marinateContract.addReward(token, amount);
    }

    function addDistributedToken(address token) external onlyAdmin {
        isDistributedToken[token] = true;
        distributedTokens.push(token);
    }

    function removeDistributedToken(address token) external onlyAdmin {
        for (uint256 i = 0; i < distributedTokens.length; i++) {
            if (distributedTokens[i] == token) {
                distributedTokens[i] = distributedTokens[distributedTokens.length - 1];
                distributedTokens.pop();
                isDistributedToken[token] = false;
            }
        }
    }

    function setMarinateAddress(address marinate) external onlyAdmin {
        marinateContract = IMarinate(marinate);
    }

    function recoverEth() external onlyAdmin {
        (bool success, ) = msg.sender.call{value: address(this).balance}("");
        require(success, "Withdraw failed");
    }

    modifier onlyAdmin() {
        require(hasRole(ADMIN_ROLE, msg.sender), "Not admin");
        _;
    }

    modifier onlyAdminOrAutomation() {
        require(hasRole(ADMIN_ROLE, msg.sender) || hasRole(AUTOMATION_ROLE, msg.sender), "Not admin or automation");
        _;
    }
}
