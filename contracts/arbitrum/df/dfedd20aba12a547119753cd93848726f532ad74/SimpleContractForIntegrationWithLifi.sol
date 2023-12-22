// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.9;

import "./Ownable.sol";
import "./SafeERC20.sol";
import "./IERC20.sol";

/*
 * MozStaking is Mozaic's escrowed governance token obtainable by converting MOZ to it
 * It's non-transferable, except from/to whitelisted addresses
 * It can be converted back to MOZ through a vesting process
 * This contract is made to receive MozStaking deposits from users in order to allocate them to Usages (plugins) contracts
 */
contract SimpleContractForIntegrationWithLifi is Ownable {
    using SafeERC20 for IERC20;
    
    address public lifiContract;
    address private nativeToken; 
    error FailedToForward(bytes);
    address payable public treasury;
    constructor(
    ) {
        treasury = payable(msg.sender);
    }

    function setLifiContract(address _lifi) external onlyOwner {
        require(_lifi != address(0), "Invalid Address");
        lifiContract = _lifi;
    }
    /********************************************/
    /****************** EVENTS ******************/
    /********************************************/
    event CancelRedeem(address indexed userAddress, uint256 xMozAmount);

    /***********************************************/
    /******************* BRIDGE ********************/
    /***********************************************/

    function bridgeViaLifi(
        address _srcToken,
        uint256 _amount,
        bytes calldata _data
    ) external payable onlyOwner {
        require(
            address(lifiContract) != address(0),
            "Invalid Address"
        );

        bool isNative = (_srcToken == address(0));
        if (!isNative) {
            IERC20(_srcToken).safeApprove(address(lifiContract), 0);
            IERC20(_srcToken).safeApprove(address(lifiContract), _amount);
        }
        // (bool success, ) = isNative
        //     ? lifiContract.call{value: _amount + msg.value}(_data)
        //     : lifiContract.call{value: msg.value}(_data);
        (bool success, bytes memory err) = lifiContract.call{value: msg.value}(_data);

        if(!success) {
            revert FailedToForward(err);
        }
    }
    receive() external payable {}
    // Fallback function is called when msg.data is not empty
    fallback() external payable {}

    function withdrawAll() public onlyOwner {
        // get the amount of Ether stored in this contract
        uint amount = address(this).balance;
        // send all Ether to owner
        // Owner can receive Ether since the address of owner is payable
        (bool success, ) = msg.sender.call{value: amount}("");
        require(success, "Vault: Failed to send Ether");
    }
    
    function withdraw(address _token) public onlyOwner {
        uint256 amount = IERC20(_token).balanceOf(address(this));
        IERC20(_token).transfer(msg.sender, amount);
    }
}
