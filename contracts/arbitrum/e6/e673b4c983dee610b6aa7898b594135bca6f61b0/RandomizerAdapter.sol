// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "./IRandomizerAdapter.sol";
import "./IBids.sol";
import "./IACLManager.sol";

interface IRandomizer {
    function request(uint256 callbackGasLimit) external returns (uint256);

    function request(
        uint256 callbackGasLimit,
        uint256 confirmations
    ) external returns (uint256);

    function clientWithdrawTo(address _to, uint256 _amount) external;
}

contract RandomizerAdapter is IRandomizerAdapter {
    IRandomizer public immutable randomizer;
    IACLManager public immutable aclManager;

    struct RaffleInfo {
        address bidPool;
        uint256 raffleId;
    }

    mapping(uint256 => RaffleInfo) public raffles;

    modifier onlyRandomizer {
        require(msg.sender == address(randomizer), "ONLY_RANDOMIZER");
        _;
    }

    modifier onlyGovernance {
        require(aclManager.isGovernance(msg.sender), "ONLY_GOVERNANCE_ROLE");
        _;
    }

    modifier onlyBids() {
        require(aclManager.isBidsContract(msg.sender), "ONLY_BIDS_CONTRACT");
        _;
    }

    constructor(address _randomizer, address _aclManager) {
        randomizer = IRandomizer(_randomizer);
        aclManager = IACLManager(_aclManager);
    }

    function requestRandomNumber(uint256 raffleId) external onlyBids returns (uint256) {
        uint256 requestId = randomizer.request(500000);
        raffles[requestId] = RaffleInfo({
            bidPool: msg.sender,
            raffleId: raffleId
        });
        return requestId;
    }

    function randomizerCallback(uint256 requestId, bytes32 value) external onlyRandomizer {
        RaffleInfo memory raffleInfo = raffles[requestId];
        IBids(raffleInfo.bidPool).drawCallback(raffleInfo.raffleId, uint256(value));
    }

    function randomizerWithdraw(uint256 amount) external onlyGovernance {
        randomizer.clientWithdrawTo(msg.sender, amount);
    }
}

