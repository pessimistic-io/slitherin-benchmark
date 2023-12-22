// SPDX-License-Identifier: UNLICENSED
//
//  :::         ...       .,-:::::  :::  .   .,::::::::::::-.      .,::::::   :::     :::  .,::      .:.,:::::::::::::::::: ::   .:  
//  ;;;      .;;;;;;;.  ,;;;'````'  ;;; .;;,.;;;;'''';;,   `';,    ;;;;''''   ;;;     ;;;  `;;;,  .,;; ;;;;'''';;;;;;;;'''',;;   ;;, 
//  [[[     ,[[     \[[,[[[         [[[[[/'   [[cccc `[[     [[     [[cccc    [[[     [[[    '[[,,[['   [[cccc      [[    ,[[[,,,[[[ 
//  $$'     $$$,     $$$$$$        _$$$$,     $$""""  $$,    $$     $$""""    $$'     $$$     Y$$$P     $$""""      $$    "$$$"""$$$ 
// o88oo,.__"888,_ _,88P`88bo,__,o,"888"88o,  888oo,__888_,o8P'     888oo,__ o88oo,.__888   oP"``"Yo,   888oo,__    88,    888   "88o
// """"YUMMM  "YMMMMMP"   "YUMMMMMP"MMM "MMP" """"YUMMMMMMP"`       """"YUMMM""""YUMMMMMM,m"       "Mm, """"YUMMM   MMM    MMM    YMM
//
// I recall the aura of mystery around LockedElixETH, the enigmatic vault of Etheria. There, elixirs crystallize
// into ethereal coins, guarded by ancient alchemist pacts. The old gates seemed to whisper secrets of the arcane,
// leaving a trace of intrigue that beckoned the curious souls. 
//       - "Mystic Brews and Ethereal Hues: Observations of an Etherian Voyage" by Eldric Etherhart

pragma solidity >=0.8.0;

import {Operatable} from "./Operatable.sol";
import {ERC20} from "./ERC20.sol";
import {SafeTransferLib} from "./SafeTransferLib.sol";
import {IElixETH} from "./IElixETH.sol";

contract LockedElixETH is ERC20, Operatable {
    using SafeTransferLib for address;
    address public elixETH;

    event Locked(address indexed account, address indexed to, uint256 amount);
    event Unlocked(address indexed account, uint256 amount);

    constructor(address _elixETH, address _owner) Operatable(_owner) {
        elixETH = _elixETH;
    }

    function lock(address to, uint256 amount) external {
        elixETH.safeTransferFrom(msg.sender, address(this), amount);
        _mint(to, amount);
        emit Locked(msg.sender, to, amount);
    }

    function unlock(address account, uint256 amount) external onlyOperators {
        _burn(account, amount);
        elixETH.safeTransfer(account, amount);
        emit Unlocked(account, amount);
    }

    function name() public pure override returns (string memory) {
        return "LockedElixETH";
    }

    function symbol() public pure override returns (string memory) {
        return "LockedElixETH";
    }
}

