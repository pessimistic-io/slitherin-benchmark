// SPDX-License-Identifier: MIT
pragma solidity ^0.8.9;

import "./AccessControl.sol";
import "./IERC20.sol";
import "./IPepePunks.sol";

contract PepePunksMinter is AccessControl {

    bytes32 public constant ADMIN_ROLE = keccak256("ADMIN_ROLE");
    uint256 public unitPrice = 4200000 ether;
    uint256 public maxCap = 10000;
    uint256 public maxPerWallet = 69;
    mapping(address => bool) public whitelist;
    bool public mintPaused;
    IPepePunks public nftContract;
    IERC20 public pepeToken;

    constructor(
        address nftContractAddress,
        address pepeTokenAddress
    ){
        nftContract = IPepePunks(nftContractAddress);
        pepeToken = IERC20(pepeTokenAddress);
        _setupRole(DEFAULT_ADMIN_ROLE, msg.sender);
    	_setupRole(ADMIN_ROLE, msg.sender);
    }

    function mint(address _to, uint _count) public {
        require(!mintPaused, "minting not started yet");
        require(nftContract.balanceOf(_to) + _count <= maxPerWallet, 'max per wallet');
        require(_count + nftContract.totalSupply() <= maxCap, "exceed maxCap");
        uint256 tokenAmount = price(_count);
        if (whitelist[_to] && nftContract.balanceOf(_to) == 0) {
            tokenAmount -= unitPrice;
        }
        require(pepeToken.balanceOf(msg.sender) >= tokenAmount, 'insufficient token balance');
        if (tokenAmount > 0) {
            require(pepeToken.transferFrom(msg.sender, address(this), tokenAmount), 'invalid token transfer');
        }
        _mint(_to, _count);
    }

    function updateWhitelist(
        address[] calldata _wallets,
        bool _allow
    ) public onlyRole(ADMIN_ROLE) {
        uint256 len = _wallets.length;
        for (uint i = 0; i < len;) {
            whitelist[_wallets[i]] = _allow;
            unchecked {
                i++;
            }
        }
    }

    function _mint(address _to, uint _count) private {
        nftContract.mint(_to, _count);
    }

    function price(uint _count) public view returns (uint256) {
        return _count * unitPrice;
    }

    function updateUnitPrice(uint256 _unitPrice) public onlyRole(ADMIN_ROLE) {
        unitPrice = _unitPrice;
    }

    function pause(bool enable) public onlyRole(ADMIN_ROLE) {
        mintPaused = enable;
    }

    function updateMaxPerWallet(uint256 val) public onlyRole(ADMIN_ROLE) {
        maxPerWallet = val;
    }

    function updateNftContrcat(IPepePunks _newAddress) public onlyRole(ADMIN_ROLE) {
        nftContract = IPepePunks(_newAddress);
    }

    function updatePepeToken(IERC20 _newAddress) public onlyRole(ADMIN_ROLE) {
        pepeToken = IERC20(_newAddress);
    }

    function updateMaxCap(uint256 _maxCap) public onlyRole(ADMIN_ROLE) {
        maxCap = _maxCap;
    }

    function ownerWithdrawTokens(uint256 amount, address _to, address _tokenAddr) public onlyRole(ADMIN_ROLE) {
        require(_to != address(0));
        if(_tokenAddr == address(0)){
            payable(_to).transfer(amount);
        } else {
            IERC20(_tokenAddr).transfer(_to, amount);
        }
    }
}

