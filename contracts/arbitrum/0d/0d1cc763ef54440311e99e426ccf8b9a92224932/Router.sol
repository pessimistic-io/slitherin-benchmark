/*
            ,« ⁿφφ╔╓,
         ,φ░╚╚    ╘▒▒▒φ,                                              
        φ░          ╠░▒▒φ        ▄▓▓▓▓▄                 █▌          ██▀▀▀
       φ             ▒░░▒▒     ▄██    ██▌  ▄▄▄▄▄    ▄▄▄▓█▌   ▄▄▄   ▐██▄▄  ▄▄   ▄▄
       ░             ╚░░░░     ██      ██ ▐█▌  ██ ▐██   █▌ ██   ██ ▐█▌    ▐█▌ ▐█▌
       ░             ░░░░▒     ██▄    ▄██ ▐█▌  ██ ▐██   █▌ ██▀▀▀▀▀ ▐█▌     ██ ██
        ░           φ░░░░       ▀██▓▓██▀  ▐█▌  ██  ▀██▓██▌  ██▓▓▓  ▐█▌      ███
         ⁿ░≥»,    ,φ░░░∩                                                  ▄▄██
           `ⁿ≥ ,«φ░≥ⁿ`                                                    
*/

// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "./IERC20.sol";
import "./SafeERC20.sol";
import "./Ownable.sol";
import "./AdapterBase.sol";

/**
// @title Ondefy Router
// @notice Acts as the registry for DEX aggregator adapters
// @author Ondefy
*/
contract Router is Ownable {
    using SafeERC20 for IERC20;
    address internal constant NATIVE = 0xEeeeeEeeeEeEeeEeEeEeeEEEeeeeEeeeeeeeEEeE;
    event NewAdapter(address adapter, uint256 index);

    struct Adapter {
        address deployedContract;
        bool isActivated;
    }

    /**
    // @dev The registry of adapters
    // 0 for 0x, 1 for 1inch, 2 for Paraswap... 
    */
    mapping(uint256 => Adapter) public adapters;

    /**
    // @dev allows contract to receive ether
    */
    receive() external payable {}

    /**
    // @dev transfer funds and data to selected adapter in order to request swap execution
    // @param _adapterIndex index of the adapter to call
    // @param _inputToken input token address
    // @param _inputTokenAmount input token amount
    // @param _outputToken output token address
    // @param _swapCallData swap callData (intended for one specific protocol)
    */
    function callAdapter(uint256 _adapterIndex, address _inputToken, uint256 _inputTokenAmount, address _outputToken, bytes memory _swapCallData) public payable {
        require(adapters[_adapterIndex].deployedContract != address(0), "ADAPTER_NOT_DEPLOYED");
        require(adapters[_adapterIndex].isActivated, "ADAPTER_NOT_ACTIVATED");
        address payable adapter = payable(adapters[_adapterIndex].deployedContract);
        if (_inputToken != NATIVE) {
            IERC20(_inputToken).safeTransferFrom(msg.sender, address(adapters[_adapterIndex].deployedContract), _inputTokenAmount);
            AdapterBase(adapter).callAction(msg.sender, _inputToken, _inputTokenAmount, _outputToken, _swapCallData);
        } else {
            AdapterBase(adapter).callAction{value: _inputTokenAmount}(msg.sender, _inputToken, _inputTokenAmount, _outputToken, _swapCallData);
        }
    }

    // Only owner functions

    /**
    // @dev activate selected adapters
    // @param index adapter index
    */
    function activateAdapter(uint256 index) public onlyOwner {
        require(adapters[index].deployedContract != address(0), "ADAPTER_NOT_DEPLOYED");
        require(!adapters[index].isActivated, "ADAPTER_ALREADY_ACTIVATED");
        adapters[index].isActivated = true;
    }

    /**
    // @dev deactivate selected adapters
    // @param index adapter index
    */
    function deactivateAdapter(uint256 index) public onlyOwner {
        require(adapters[index].deployedContract != address(0), "ADAPTER_NOT_DEPLOYED");
        require(adapters[index].isActivated, "ADAPTER_ALREADY_DEACTIVATED");
        adapters[index].isActivated = false;
    }

    /**
    // @dev modify adapter at given index
    // @param index adapter index
    // @param _deployedContract address of the deployed contract
    // @param _isActivated true for activating right away, false otherwise
    // @dev an adapter must be already present at given index
    */
    function modifyAdapter(uint256 index, address _deployedContract, bool _isActivated) public onlyOwner {
        adapters[index].deployedContract = _deployedContract;
        adapters[index].isActivated = _isActivated;
        emit NewAdapter(_deployedContract, index);
    }

    /**
    // @dev add adapter at given index
    // @param index adapter index
    // @param _deployedContract address of the deployed contract
    // @param _isActivated true for activating right away, false otherwise
    // @dev no adapter should be already present at given index
    */
    function addAdapter(uint256 index, address _deployedContract, bool _isActivated) public onlyOwner {
        require(adapters[index].deployedContract == address(0), "EXISTING_ADAPTER_AT_GIVEN_INDEX");
        modifyAdapter(index, _deployedContract, _isActivated);
    }

    /**
    // @dev set fee rate for selected adapter
    // @param index adapter index
    // @param _feeRateBps fee rate in bps
    */
    function setFeeRate(uint256 index, uint8 _feeRateBps) public onlyOwner {
        AdapterBase(payable(adapters[index].deployedContract)).setFeeRate(_feeRateBps);
    }

    /**
    // @dev transfer contract funds to userAddress
    // @param token token address. See NATIVE constant above for native asset transfer.
    // @param recipient recipient of the transfer
    // @param amount amount to transfer
    */
    function rescueFunds(address token, address recipient, uint256 amount) public onlyOwner {
        if (token != NATIVE) {
            IERC20(token).safeTransfer(recipient, amount);
        } else {
            payable(recipient).transfer(amount);
        }
    }

    /**
    // @dev transfer adapter funds to userAddress
    // @param index adapter index
    // @param token token address. See NATIVE constant above for native asset transfer.
    // @param recipient recipient of the transfer
    // @param amount amount to transfer
    */
    function redeemAdapterFunds(uint256 index, address token, address recipient, uint256 amount) public onlyOwner {
        AdapterBase(payable(adapters[index].deployedContract)).rescueFunds(token, recipient, amount);
    }

    /**
    // @dev transfer given adapater governance to _newGovernance
    // @param index adapter index
    // @param _newGovernance address of the new governance contract
    // @dev the new governance contract must implement necessary functions to manage adapter governance and actions
    */
    function transferGovernance(uint256 index, address _newGovernance) public onlyOwner {
        AdapterBase(payable(adapters[index].deployedContract)).transferGovernance(_newGovernance);
    }
}

