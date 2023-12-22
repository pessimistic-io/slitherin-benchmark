// SPDX-License-Identifier: UNLICENSED

pragma solidity 0.8.18;

import {Initializable} from "./Initializable.sol";
import {OwnableUpgradeable} from "./OwnableUpgradeable.sol";

contract LevelReferralRegistry is Initializable, OwnableUpgradeable {
    mapping(address trader => address referrer) public referredBy;
    mapping(address trader => uint256 timeSet) public referredSetTime;
    mapping(address trader => uint256 timeSet) public chainToClaimSetTime;

    address public controller;

    constructor() {
        _disableInitializers();
    }

    function initialize() external initializer {
        __Ownable_init();
    }

    // =============== USER FUNCTIONS ===============
    function setReferrer(address _trader, address _referrer) external {
        require(msg.sender == controller, "!controller");
        if (_trader != address(0) && _referrer != address(0) && _trader != _referrer && referredBy[_trader] == address(0)) {
            referredBy[_trader] = _referrer;
            referredSetTime[_trader] = block.timestamp;
            emit ReferrerSet(_trader, _referrer);
        }
    }

    function setChainToClaimRewards() external {
        chainToClaimSetTime[msg.sender] = uint64(block.timestamp);
        emit SetChainToClaimRewards(msg.sender);
    }

    function setController(address _controller) external onlyOwner {
        require(_controller != address(0), "invalid address");
        controller = _controller;
        emit ControllerSet(controller);
    }

    // ===============  EVENTS ===============
    event ReferrerSet(address indexed trader, address indexed referrer);
    event ControllerSet(address indexed updater);
    event SetChainToClaimRewards(address indexed user);
}

