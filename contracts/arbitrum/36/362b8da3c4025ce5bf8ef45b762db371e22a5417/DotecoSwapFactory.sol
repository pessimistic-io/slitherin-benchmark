// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.0;

import "./Ownable.sol";
import "./DotecoSwap.sol";

contract DotecoSwapFactory is Ownable {
  	mapping(address => address[]) public ownerToSwaps;
    uint256 public swapFee = 0.1 ether;

    event SwapCreated(address swapAddress);

    // allow contract to receive ether, msg.data is empty
    receive() external payable {}

    //allow contract to receive ether, msg.data is not empty
    fallback() external payable {}

    function createSwap(
        address _token1,
        address _owner1,
        uint256 _amount1,
        address _token2,
        address _owner2,
        uint256 _amount2
    ) 
		external 
	{
        DotecoSwap swap = new DotecoSwap(
            address(this),
            _token1,
            _owner1,
            _amount1,
            _token2,
            _owner2,
            _amount2,
            swapFee
        );

        address swapAddress = address(swap);
        ownerToSwaps[_owner1].push(swapAddress);
        ownerToSwaps[_owner2].push(swapAddress);

        emit SwapCreated(swapAddress);
    }

    function getSwapsForUser(address owner)
        external
        view
        returns (address[] memory)
    {
        return ownerToSwaps[owner];
    }

    function payoutFees(address payable payeeAddress) external onlyOwner {
        (bool success, ) = payeeAddress.call{value: getBalance()}("");
        require(success, "DotecoSwapFactory::Fee payout failed");
    }

    function setSwapFee(uint256 _swapFee) external onlyOwner {
        swapFee = _swapFee;
    }

	function getBalance() public view returns (uint256) {
        return address(this).balance;
    }
}

