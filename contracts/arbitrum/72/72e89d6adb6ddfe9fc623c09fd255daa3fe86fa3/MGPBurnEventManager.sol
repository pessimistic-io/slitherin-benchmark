// SPDX-License Identifire: MIT
pragma solidity ^0.8.0;

import { SafeERC20 } from "./SafeERC20.sol";
import { IERC20 } from "./ERC20.sol";
import {OwnableUpgradeable} from "./OwnableUpgradeable.sol";
import { Initializable } from "./Initializable.sol";
import { ReentrancyGuardUpgradeable } from "./ReentrancyGuardUpgradeable.sol";
import { PausableUpgradeable } from "./PausableUpgradeable.sol";
import { Address } from "./Address.sol";

contract MGPBurnEventManager is
    Initializable,
    OwnableUpgradeable,
    ReentrancyGuardUpgradeable,
    PausableUpgradeable
{
    using SafeERC20 for IERC20;

    /* ============ State Variables ============ */

    address public blackHole;
    address public mgp;

    uint256 public numberOfEvents;

    struct EventInfo
    {
        uint256 eventId;
        string eventName;
        uint256 totalMgpBurned;
        uint256 eventEndTime;
        bool isActive;
    }

    /* ============ Events ============ */

    event eventStartedAndActivated( uint256 eventId, string eventName, bool isActive, uint256 eventEndTime );
    event eventDeActivated( uint256 eventId, string eventName, bool isActivem, uint256 eventEndTime );
    event eventJoinedSuccesfully( address user, uint256 eventId, uint256 mgpBurnAmount );

    /* ============ Errors ============ */
    
    error eventIsNotActive();
    error eventNotExist();
    error eventWithSameNameExist();
    error IsZeroAddress();
    error IsZeroAmount();
    error IsNotSmartContractAddress();
    error InvalidEventDeactivateTime();

    /* ============ Constructor ============ */

    mapping(uint256 =>  EventInfo) public eventInfos;
    mapping(address => mapping(uint256 => uint256)) public userMgpBurnAmountForEvent;
    mapping(string => bool) public isEventWithNameActive;
    uint256[50] private __gap;

    constructor(){
        _disableInitializers();
    }
    
    function __MGPBurnEventManager_init(address _blackHole, address _mgp) public initializer {
        __Ownable_init();
        __ReentrancyGuard_init();
        __Pausable_init();
        if(! Address.isContract(_blackHole)) revert IsNotSmartContractAddress();
        if(_mgp == address(0)) revert IsZeroAddress();
        blackHole = _blackHole;
        mgp = _mgp;
    }

    /* ============ External Read Functions ============ */

    /* ============ External Write Functions ============ */

    function joinEvent(uint256 _eventId, uint256 _mgpBurnAmount) external whenNotPaused nonReentrant
    {
        _joinEvent(msg.sender, _eventId, _mgpBurnAmount);
    }

    function joinEventFor(address _user, uint256 _eventId, uint256 _mgpBurnAmount) external whenNotPaused nonReentrant
    {
        _joinEvent(_user, _eventId, _mgpBurnAmount);
    }

    /* ============ Internal Functions ============ */

    function _joinEvent(address _user, uint256 _eventId, uint256 _mgpBurnAmount) internal {
        EventInfo storage eventInfo = eventInfos[_eventId];

        if(_mgpBurnAmount == 0) revert IsZeroAmount();
        if(eventInfo.eventId == 0) revert eventNotExist();
        if(eventInfo.isActive == false || block.timestamp >= eventInfo.eventEndTime ) revert eventIsNotActive();

        IERC20(mgp).safeTransferFrom(msg.sender, blackHole, _mgpBurnAmount);

        eventInfo.totalMgpBurned += _mgpBurnAmount;
        userMgpBurnAmountForEvent[_user][_eventId] += _mgpBurnAmount; // User burned MGP amount for given event id

        emit eventJoinedSuccesfully(_user, _eventId, _mgpBurnAmount);
    }

    /* ============ Admin Functions ============ */

    function pause() external onlyOwner {
        _pause();
    }

    function unpause() external onlyOwner {
        _unpause();
    }

    function startNewEvent( string memory _eventName, uint256 _eventDeactivateTime ) external onlyOwner returns( uint256 ) {
        if(isEventWithNameActive[_eventName] == true) revert eventWithSameNameExist();
        if(_eventDeactivateTime <= block.timestamp) revert InvalidEventDeactivateTime();

        numberOfEvents++;
        EventInfo storage eventInfo = eventInfos[numberOfEvents];

        eventInfo.eventId = numberOfEvents;
        eventInfo.eventName = _eventName;
        eventInfo.isActive = true;
        eventInfo.eventEndTime = _eventDeactivateTime;
        isEventWithNameActive[_eventName] = true;

        emit eventStartedAndActivated(eventInfo.eventId, _eventName, true, _eventDeactivateTime );
                
        return eventInfo.eventId;
    }

    function deActivateEvent(uint256 _eventId) external onlyOwner {
        EventInfo storage eventInfo = eventInfos[_eventId];

        if(eventInfo.eventId == 0) revert eventNotExist();
        if(eventInfo.isActive == false || block.timestamp >= eventInfo.eventEndTime) revert eventIsNotActive();

        eventInfo.isActive = false; 
        isEventWithNameActive[eventInfo.eventName]  = false;

        emit eventDeActivated(_eventId, eventInfo.eventName, false, eventInfo.eventEndTime);
    }
}
