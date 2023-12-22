// SPDX-License-Identifier: MIT
// An example of a consumer contract that relies on a subscription for funding.
pragma solidity ^0.8.7;
import "./AccessControl.sol";
import "./IYDTSwapLottery.sol";

interface IRandomizer {
    function request(uint256 callbackGasLimit) external returns (uint256);
    function request(uint256 callbackGasLimit, uint256 confirmations) external returns (uint256);
    function clientWithdrawTo(address _to, uint256 _amount) external;
}

contract RandomNumberGenerator is AccessControl
{
    IYDTSwapLottery public YDTLottery;
    uint256 public latestLotteryId;
    event RequestSent(uint256 requestId, uint32 numWords);
    event RequestFulfilled(uint256 requestId, uint256 randomWords);

    // past requests Id.
    uint256[] public requestIds;
    uint256 public lastRequestId;

    uint32 callbackGasLimit = 50000;

    uint256 public randomResult;

    // The default is 3, but you can set this higher.
    uint16 requestConfirmations = 3;

    
    uint32 numWords = 1;
    address public YDTLotteryAdd;


    IRandomizer public randomizer;
    

    constructor(address _randomizer)
    {
        randomizer = IRandomizer(_randomizer);
        _grantRole(DEFAULT_ADMIN_ROLE, msg.sender);
    }

    function getRandomNumber()
        external
        returns (uint256 requestId)
    {
        require(msg.sender == YDTLotteryAdd, "Only YDTLottery");
        requestId = randomizer.request(callbackGasLimit);
        requestIds.push(requestId);
        lastRequestId = requestId;
        emit RequestSent(requestId, numWords);
        return requestId;
    }

    // Callback function called by the randomizer contract when the random value is generated
		function randomizerCallback(uint256 _id, bytes32 _value) external {
			require(msg.sender == address(randomizer), "Caller not Randomizer");
            randomResult = (1000000 + (uint256(_value) % 1000000));
            latestLotteryId = YDTLottery.viewCurrentLotteryId();
            emit RequestFulfilled(_id, randomResult);
		}
		
		// Allows the owner to withdraw their deposited randomizer funds
		function randomizerWithdraw(uint256 amount)
		external
		onlyRole(DEFAULT_ADMIN_ROLE)
		{
			randomizer.clientWithdrawTo(msg.sender, amount);
		}


    /**
     * @notice Set the address for the YDTLottery
     * @param _YDTLottery: address of the YDT lottery contract
     */
    function setLotteryAddress(address _YDTLottery) external onlyRole(DEFAULT_ADMIN_ROLE) {
        YDTLottery = IYDTSwapLottery(_YDTLottery);
        YDTLotteryAdd = _YDTLottery;
    }

    /**
     * @notice View latestLotteryId
     */
    function viewLatestLotteryId() external view returns (uint256) {
        return latestLotteryId;
    }

    /**
     * @notice View random result
     */
    function viewRandomResult() external view returns (uint256) {
        return randomResult;
    }
}
