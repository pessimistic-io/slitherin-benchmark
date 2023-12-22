// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.7.0;

contract State {
    enum StateType {INITIALIZED, READY, ONGOING, SUCCESS, FAIL, PAUSED}

    StateType public state;
    StateType public stateBeforePause;

    modifier onlyDuringInitialized() {
        _isInitializedState();
        _;
    }

    function _isInitializedState() internal view {
        require(state == StateType.INITIALIZED, "ONLY_DURING_INITIALIZED");
    }

    modifier onlyDuringReady() {
        _isReadyState();
        _;
    }

    function _isReadyState() internal view {
        require(state == StateType.READY, "ONLY_DURING_READY");
    }    

    modifier onlyDuringOngoing() {
        _isOngoingState();
        _;
    }

    function _isOngoingState() internal view {
        require(state == StateType.ONGOING, "ONLY_DURING_ONGOING");
    }

    modifier onlyDuringSuccess() {
        _isSuccessState();
        _;
    }

    function _isSuccessState() internal view {
        require(state == StateType.SUCCESS, "ONLY_DURING_SUCCESS");
    }

    modifier onlyDuringFail() {
        _isFailState();
        _;
    }

    function _isFailState() internal view {
        require(state == StateType.FAIL, "ONLY_DURING_FAIL");
    }

    modifier onlyDuringPaused() {
        _isPausedState();
        _;
    }

    function _isPausedState() internal view {
        require(state == StateType.PAUSED, "ONLY_DURING_PAUSED");
    }
}
