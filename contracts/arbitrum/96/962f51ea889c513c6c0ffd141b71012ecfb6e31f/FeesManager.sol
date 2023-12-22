// SPDX-License-Identifier: MIT
pragma solidity ^0.8.18;

import {Ownable} from "./Ownable.sol";
import {IERC20} from "./IERC20.sol";
import {Initializable} from "./Initializable.sol";

contract FeesManager is Ownable, Initializable {
    // ====== States ======
    uint256 public feesBps = 5;

    // ====== Constructor ======
    function initialize(address owner) external initializer {
        _transferOwnership(owner);
    }

    // ====== Methods ====== //
    function withdraw(IERC20 token, uint256 amount) external onlyOwner {
        token.transfer(owner(), amount);
    }

    function setFeeBps(uint256 newBps) external onlyOwner {
        feesBps = newBps;
    }

    fallback() external {}

    receive() external payable {}
}

