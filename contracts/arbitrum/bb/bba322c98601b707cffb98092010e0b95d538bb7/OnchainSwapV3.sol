// SPDX-License-Identifier: GPL-3.0

pragma solidity ^0.8.0;

import "./Context.sol";
import "./IERC20.sol";
import "./OnchainGateway.sol";
import "./Ownable.sol";



contract OnchainSwapV3  is Context, Ownable{

    uint256 public fee = 0.05 ether;

    event ClaimedTokens(address token, address owner, uint256 balance);
    event OnchainSwap(address token, uint256 amount, uint256 fee);

    OnchainGateway public immutable onchainGateway;

    constructor() {
        onchainGateway = new OnchainGateway(address(this));
    }

    modifier hasFee() {
        require(msg.value >= fee);
        _;
    }

    function onswap(
        address token,
        uint amount,
        address dex,
        address dexgateway,
        bytes memory calldata_
    ) external payable hasFee {

        if(token!=address(0)) {
            onchainGateway.claimTokens(
                token,
                _msgSender(),
                amount
            );

            if (dexgateway == address(0)) {
                IERC20(token).approve(dex, amount);
            } else {
                IERC20(token).approve(dexgateway, amount);
            }
        }

        require(dex != address(onchainGateway), "OnchainSwap: call to onchain gateway");

        {
                uint256 size;
                address toCheck = dex;

                assembly {
                    size := extcodesize(toCheck)
                }

                require(size != 0, "OnchainSwap: call for a non-contract account");
            }


        (bool swapPassed, ) = dex.call{value: msg.value - fee}(
            calldata_
        );

        require(swapPassed, "OnchainSwap: Fail to call");
        emit OnchainSwap(token, amount, fee);
    }

    function changeFee(uint256 _newFee) public onlyOwner {
        fee = _newFee;
    }

    function claimTokens(address _token) public onlyOwner {
        if (_token == address(0x0)) {
            (bool sent, ) = _msgSender().call{value: address(this).balance}("");
            require(sent, "Failed to send Ether");
            return;
        }
        IERC20 erc20token = IERC20(_token);
        uint256 balance = erc20token.balanceOf(address(this));
        erc20token.transfer(_msgSender(), balance);
        emit ClaimedTokens(_token, _msgSender(), balance);
    }
}

