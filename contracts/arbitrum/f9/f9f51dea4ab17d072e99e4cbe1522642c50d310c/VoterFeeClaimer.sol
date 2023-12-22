// SPDX-License-Identifier: MIT
pragma solidity ^0.8.7;

import "./AutomationCompatible.sol";
import "./IVoter.sol";
import "./OwnableUpgradeable.sol";


contract VoterFeeClaimer is AutomationCompatibleInterface, OwnableUpgradeable  {

    address public automationRegistry;

    address[] public voters; // should contain 2 voter addresses (foxVoter, foxBluechipVoter)
    uint256 public interval; // claim interval
    uint256 public maxGaugesPerTx;
    mapping(uint256 => mapping(address => uint256)) public noOfClaims; // period => voter => noOfClaims
    mapping(uint256 => mapping(address => bool)) public isClaimed; // period => voter => isClaimed
    bool public isPaused;

    constructor() {}

    function initialize(
        address[] calldata _voters
    ) public initializer {
        __Ownable_init();
        automationRegistry = address(0x75c0530885F385721fddA23C539AF3701d6183D4);
        interval = 86400; // once per day
        maxGaugesPerTx = 20;

        for (uint i = 0; i < _voters.length; i++) {
            voters.push(_voters[i]);
        }
    }

    function getPeriod() public view returns (uint256) {
        return (block.timestamp / interval) * interval;
    }

    function checkUpkeep(bytes memory /*checkdata*/) public view override returns (bool upkeepNeeded, bytes memory /*performData*/) {
        if (!isPaused) {
            uint256 _period = getPeriod();
            for (uint i = 0; i < voters.length; i++) {
                if (!isClaimed[_period][voters[i]]) {
                    upkeepNeeded = true;
                    break;
                }
            }
        }
    }

    function performUpkeep(bytes calldata /*performData*/) external override {
        require(msg.sender == automationRegistry || msg.sender == owner(), 'cannot execute');
        (bool upkeepNeeded, ) = checkUpkeep('0');
        require(upkeepNeeded, "condition not met");

        address _voter;
        uint256 _period = getPeriod();
        for (uint i = 0; i < voters.length; i++) {
            _voter = voters[i];
            if (!isClaimed[_period][_voter]) {
                uint256 _offset = noOfClaims[_period][_voter];
                uint256 _len = IVoter(_voter).length();
                uint256 _gaugesToProcess = _len - _offset;

                if (_gaugesToProcess > maxGaugesPerTx) {
                    _gaugesToProcess = maxGaugesPerTx;
                } else {
                    isClaimed[_period][_voter] = true;
                }

                noOfClaims[_period][_voter] += _gaugesToProcess;
                address[] memory _gauges = new address[](_gaugesToProcess);

                for (uint256 j = 0; j < _gaugesToProcess; j++) {
                    _gauges[j] = IVoter(_voter).gaugeList(_offset + j);
                }

                IVoter(_voter).distributeFees(_gauges);
                break;
            }
        }
    }

    function setAutomationRegistry(address _automationRegistry) external onlyOwner {
        require(_automationRegistry != address(0));
        automationRegistry = _automationRegistry;
    }

    function addVoter(address _voter) external onlyOwner {
        require(_voter != address(0));
        voters.push(_voter);
    }

    function removeVoter() external onlyOwner {
        voters.pop();
    }

    function setInterval(uint256 _interval) external onlyOwner {
        require(_interval >= 86400);
        interval = _interval;
    }

    function setMaxPerTx(uint256 _maxGaugesPerTx) external onlyOwner {
        maxGaugesPerTx = _maxGaugesPerTx;
    }

    function flipPause() external onlyOwner {
        isPaused = !isPaused;
    }

}
