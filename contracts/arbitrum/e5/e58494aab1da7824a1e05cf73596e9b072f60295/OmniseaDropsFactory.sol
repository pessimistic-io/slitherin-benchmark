// SPDX-License-Identifier: MIT

pragma solidity ^0.8.7;

import "./IOmniseaERC721Psi.sol";
import "./OmniseaERC721PsiProxy.sol";
import "./IOmniseaDropsFactory.sol";
import { CreateParams } from "./ERC721Structs.sol";
import "./ReentrancyGuard.sol";

contract OmniseaDropsFactory is IOmniseaDropsFactory, ReentrancyGuard {
    address internal _manager;
    address public owner;
    address public scheduler;
    address public universalONFT;
    address public omniseaERC721Psi;
    mapping(address => bool) public drops;

    event Created(address indexed collection);

    constructor(address _scheduler, address _universalONFT, address _omniseaERC721Psi) {
        owner = msg.sender;
        scheduler = _scheduler;
        universalONFT = _universalONFT;
        omniseaERC721Psi = _omniseaERC721Psi;
    }

    function create(CreateParams calldata _params) external override nonReentrant {
        OmniseaERC721PsiProxy proxy = new OmniseaERC721PsiProxy(omniseaERC721Psi);
        address proxyAddress = address(proxy);
        IOmniseaERC721Psi(proxyAddress).initialize(_params, msg.sender, _manager, scheduler, universalONFT);
        drops[proxyAddress] = true;
        emit Created(proxyAddress);
    }

    function setManager(address manager_) external {
        require(msg.sender == owner);
        _manager = manager_;
    }
}

