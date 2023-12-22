// SPDX-License-Identifier: UNLICENSED

pragma solidity ^0.8.6;

import "./Ownable.sol";
import "./SafeERC20.sol";
error InvalidVRFCost();

interface IRandomizer {
    function request(
        uint128 callbackGasLimit
    ) external payable returns (uint256);

    function estimateFee(
        uint256 callbackGasLimit
    ) external view returns (uint256);
}


contract TestBaseGame is Ownable {
    using SafeERC20 for IERC20;

    event ResolveRequest(uint256 id,bytes32 randomness);
    event RequestRandomness(uint256 id,uint256 confirmations);
    event DeductVRFFee(uint256 sent, uint256 cost);

    IRandomizer public randomizer;

    struct _state {
        uint256 requestId;
        bool resolved;
        bytes32 randomness;
    }
    mapping(uint256 => _state) public requests;

    /* Guardian */
    constructor(
        address _randomizer
    ) {
        randomizer = IRandomizer(_randomizer);
    }

    function recoverTokens(address token) external onlyOwner {
        if (token == address(0)) {
            payable(msg.sender).transfer(address(this).balance);
        } else {
            IERC20(token).safeTransfer(
                msg.sender,
                IERC20(token).balanceOf(address(this))
            );
        }
    }

    /* VRF */
    function _deductVRFCost(uint256 sentVRFGas) internal {
        uint256 VRFCost = getVRFCost();
        if (sentVRFGas < VRFCost) {
            revert InvalidVRFCost();
        }

        emit DeductVRFFee(sentVRFGas, VRFCost);
    }

    
    function randomizerCallback(uint256 randomId, bytes32 _value) external {
        require(
            msg.sender == address(randomizer),
            "Only the randomizer contract can call this function"
        );
        requests[randomId] =  _state(randomId,true,_value);


        emit ResolveRequest(randomId,_value);
    }

    function requestRandomValues(uint32) public returns (uint256 requestId) {
        requestId = randomizer.request{value: getVRFCost()}(
            750_000
        );
        requests[requestId].requestId = requestId;
        requests[requestId].resolved = false;
        requests[requestId].randomness = bytes32(uint256(0));

        emit RequestRandomness(requestId, 1);

        return requestId;
    }

    function getVRFCost() public view returns (uint256) {
        return randomizer.estimateFee(750_000);
    }


    /* Gas Token */
    fallback() external payable {}

    receive() external payable {}
}

