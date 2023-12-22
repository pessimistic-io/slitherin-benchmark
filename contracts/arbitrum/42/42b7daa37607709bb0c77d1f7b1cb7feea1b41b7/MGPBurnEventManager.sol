// SPDX-License Identifire: MIT
pragma solidity ^0.8.0;

import { SafeERC20 } from "./SafeERC20.sol";
import { IERC20 } from "./ERC20.sol";
import { OwnableUpgradeable } from "./OwnableUpgradeable.sol";
import { Initializable } from "./Initializable.sol";
import { ReentrancyGuardUpgradeable } from "./ReentrancyGuardUpgradeable.sol";
import { PausableUpgradeable } from "./PausableUpgradeable.sol";


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
        bool isActive;
    }

    /* ============ Events ============ */

    event eventStartedAndActivated( uint256 eventId, string eventName, bool isActive );
    event eventDeActivated( uint256 eventId, string eventName, bool isActive );
    event eventJoinedSuccesfully( address user, uint256 eventId, uint256 mgpBurnAmount );

    /* ============ Errors ============ */

    error eventIsNotActive();
    error eventNotExist();
    error eventWithSameNameExist();

    /* ============ Constructor ============ */

    mapping( uint256 =>  EventInfo) public eventInfos;
    mapping(address => mapping(uint256 => uint256)) public userMgpBurnAmountForEvent;
    mapping(string => bool) public isEventWithNameActive;

    function __MGPBurnEventManager_init(address _blackHole, address _mgp) public initializer {
        __Ownable_init();
        __ReentrancyGuard_init();
        __Pausable_init();
        blackHole = _blackHole;
        mgp = _mgp;
    }

    /* ============ External Read Functions ============ */

    /* ============ External Write Functions ============ */

    function joinEvent(uint256 _eventId, uint256 _mgpBurnAmount) external whenNotPaused nonReentrant
    {
        EventInfo storage eventInfo = eventInfos[_eventId];

        if(eventInfo.eventId == 0) revert eventNotExist();
        if(eventInfo.isActive == false) revert eventIsNotActive();

        eventInfo.totalMgpBurned += _mgpBurnAmount;
        userMgpBurnAmountForEvent[msg.sender][_eventId] += _mgpBurnAmount; // User burned MGP amount for given event id

        IERC20(mgp).safeTransferFrom(msg.sender, blackHole, _mgpBurnAmount);

        emit eventJoinedSuccesfully(msg.sender, _eventId, _mgpBurnAmount);
    }

    function joinEventFor(address _user, uint256 _eventId, uint256 _mgpBurnAmount) external whenNotPaused nonReentrant
    {
        EventInfo storage eventInfo = eventInfos[_eventId];

        if(eventInfo.eventId == 0) revert eventNotExist();
        if(eventInfo.isActive == false) revert eventIsNotActive();

        eventInfo.totalMgpBurned += _mgpBurnAmount;
        userMgpBurnAmountForEvent[_user][_eventId] += _mgpBurnAmount; // User burned MGP amount for given event id

        IERC20(mgp).safeTransferFrom(msg.sender, blackHole, _mgpBurnAmount);

        emit eventJoinedSuccesfully(_user, _eventId, _mgpBurnAmount);
    }

    /* ============ Internal Functions ============ */

    /* ============ Admin Functions ============ */

    function pause() external onlyOwner {
        _pause();
    }

    function unpause() external onlyOwner {
        _unpause();
    }

    function startNewEvent( string memory _eventName ) external onlyOwner returns( uint256 ) {
        if(isEventWithNameActive[_eventName] == true) revert eventWithSameNameExist();
        numberOfEvents++;

        EventInfo storage eventInfo = eventInfos[numberOfEvents];

        eventInfo.eventId = numberOfEvents;
        eventInfo.eventName = _eventName;
        eventInfo.isActive = true;
        isEventWithNameActive[_eventName] = true;

        emit eventStartedAndActivated(  eventInfo.eventId, _eventName, true );
                
        return eventInfo.eventId;
    }

    function deActivateEvent(uint256 _eventId) external onlyOwner {
        EventInfo storage eventInfo = eventInfos[_eventId];

        if(eventInfo.eventId == 0) revert eventNotExist();
        if(eventInfo.isActive == false) revert eventIsNotActive();

        eventInfo.isActive = false; 
        isEventWithNameActive[eventInfo.eventName]  = false;

        emit eventDeActivated( _eventId, eventInfo.eventName, false);
    }
}
