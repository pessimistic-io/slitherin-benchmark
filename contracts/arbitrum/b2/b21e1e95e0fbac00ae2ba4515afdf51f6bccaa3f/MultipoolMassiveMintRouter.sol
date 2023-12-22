// SPDX-License-Identifier: GPL-3.0
pragma solidity ^0.8.0;

import {Multipool, MpAsset as UintMpAsset, MpContext as UintMpContext} from "./Multipool.sol";
import "./IUniswapV2Pair.sol";
import "./IERC20.sol";
import {Ownable} from "./Ownable.sol";
import {ReentrancyGuard} from "./ReentrancyGuard.sol";

contract MultipoolMassiveMintRouter is Ownable, ReentrancyGuard {
    constructor() Ownable(msg.sender) {}

    mapping(address => bool) isContractAllowedToCall;

    function approveToken(address token, address to) public onlyOwner {
        IERC20(token).approve(to, type(uint).max);
    }

    function toggleContract(address addr) public onlyOwner {
        isContractAllowedToCall[addr] = !isContractAllowedToCall[addr];
    }

    struct CallParams {
        bytes targetData;
        address target;
        uint ethValue;
    }

    function massiveMint(
        address poolAddress,
        address tokenFrom,
        uint amount,
        uint minShareOut,
        CallParams[] calldata params,
        address[] calldata multipoolAddresses,
        address to
    ) public payable nonReentrant {
        IERC20(tokenFrom).transferFrom(msg.sender, address(this), amount);
        for (uint i = 0; i < params.length; i++) {
            require(isContractAllowedToCall[params[i].target], "MULTIPOOL_MASS_ROUTER: IA");
            (bool success,) = params[i].target.call{value: params[i].ethValue}(params[i].targetData);
            require(success, "MULTIPOOL_MASS_ROUTER: CF");
        }
        uint share = Multipool(poolAddress).massiveMint(multipoolAddresses, to);
        require(minShareOut <= share, "MULTIPOOL_MASS_ROUTER: SE");
    }
}

