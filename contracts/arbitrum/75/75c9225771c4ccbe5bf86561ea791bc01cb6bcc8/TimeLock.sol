// SPDX-License-Identifier: MIT

pragma solidity 0.6.12;

import "./Ownable.sol";

contract TimeLock is Ownable {
    bool public WAIT_FOR_UNLOCK;
    uint public UNLOCK_TIMESTAMP;

    address public CONTRACT_ADDRESS;
    uint constant public TIMELOCK_PERIOD = 12 hours;

    constructor(
        address _contractAddress
    ) public {
        CONTRACT_ADDRESS = _contractAddress;
    }
    
    modifier hasTimeLock() {
        require(WAIT_FOR_UNLOCK, "Unlock not initialized");
        require(block.timestamp >= UNLOCK_TIMESTAMP, "Waiting for unlock");
        _;
        WAIT_FOR_UNLOCK = false;
    }

    function unlock() external onlyOwner {
        WAIT_FOR_UNLOCK = true;
        UNLOCK_TIMESTAMP = TIMELOCK_PERIOD + block.timestamp;
    }

    function setSettings(
        uint256 _controllerFee,
        uint256 _rewardRate,
        uint256 _buyBackRate,
        uint256 _withdrawFeeFactor,
        uint256 _slippageFactor,
        address _uniRouterAddress
    ) external hasTimeLock onlyOwner {
        IStrat(CONTRACT_ADDRESS).setSettings(_controllerFee, _rewardRate, _buyBackRate, _withdrawFeeFactor, _slippageFactor, _uniRouterAddress);
    }

    function setGov(address _govAddress) external hasTimeLock onlyOwner {
        IStrat(CONTRACT_ADDRESS).setGov(_govAddress);
    }

    function pause() external hasTimeLock onlyOwner {
        IStrat(CONTRACT_ADDRESS).pause();
    }

    function unpause() external hasTimeLock onlyOwner {
        IStrat(CONTRACT_ADDRESS).unpause();
    }

    function resetAllowances() external hasTimeLock onlyOwner {
        IStrat(CONTRACT_ADDRESS).resetAllowances();
    }

    function panic() external hasTimeLock onlyOwner {
        IStrat(CONTRACT_ADDRESS).panic();
    }

    function unpanic() external hasTimeLock onlyOwner {
        IStrat(CONTRACT_ADDRESS).unpanic();
    }
}

interface IStrat {
   function setSettings(uint256,uint256,uint256,uint256,uint256,address) external; 
   function setGov(address) external;
   function pause() external;
   function unpause() external;
   function resetAllowances() external;
   function panic() external;
   function unpanic() external;
}
