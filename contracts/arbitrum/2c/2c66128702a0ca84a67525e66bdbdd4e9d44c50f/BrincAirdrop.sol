// SPDX-License-Identifier: MIT
pragma solidity 0.6.12;

import "./Ownable.sol";
import "./MerkleProof.sol";
import "./IERC20.sol";
import "./SafeERC20.sol";

contract BrincAirdrop is Ownable {
    using SafeERC20 for IERC20;

    IERC20 public gbrc;

    bytes32 public merkleRoot1;
    bytes32 public merkleRoot2;
    bytes32 public merkleRoot3;

    mapping(address => bool) public claimed1;
    mapping(address => bool) public claimed2;
    mapping(address => bool) public claimed3;

    constructor(IERC20 _gbrc) public {
        require(address(_gbrc) != address(0), "invalid gbrc address");
        gbrc = _gbrc;
    }

    function claim1(uint256 _amount, bytes32[] calldata _merkleProof) public {
        require(merkleRoot1 != 0x0, "merkleRoot not set");
        require(!claimed1[msg.sender], "already claimed");

        bytes32 leaf = keccak256(abi.encodePacked(msg.sender, _amount));
        require(MerkleProof.verify(_merkleProof, merkleRoot1, leaf), "invalid proof");

        claimed1[msg.sender] = true;

        gbrc.safeTransfer(msg.sender, _amount);
    }

    function claim2(uint256 _amount, bytes32[] calldata _merkleProof) public {
        require(merkleRoot2 != 0x0, "merkleRoot not set");
        require(!claimed2[msg.sender], "already claimed");

        bytes32 leaf = keccak256(abi.encodePacked(msg.sender, _amount));
        require(MerkleProof.verify(_merkleProof, merkleRoot2, leaf), "invalid proof");

        claimed2[msg.sender] = true;

        gbrc.safeTransfer(msg.sender, _amount);
    }

    function claim3(uint256 _amount, bytes32[] calldata _merkleProof) public {
        require(merkleRoot3 != 0x0, "merkleRoot not set");
        require(!claimed3[msg.sender], "already claimed");

        bytes32 leaf = keccak256(abi.encodePacked(msg.sender, _amount));
        require(MerkleProof.verify(_merkleProof, merkleRoot3, leaf), "invalid proof");

        claimed3[msg.sender] = true;

        gbrc.safeTransfer(msg.sender, _amount);
    }

    function setRootHash1(bytes32 _merkleRoot) public onlyOwner {
        merkleRoot1 = _merkleRoot;
    }

    function setRootHash2(bytes32 _merkleRoot) public onlyOwner {
        merkleRoot2 = _merkleRoot;
    }

    function setRootHash3(bytes32 _merkleRoot) public onlyOwner {
        merkleRoot3 = _merkleRoot;
    }

    function withdrawGBRC(IERC20 _token) public onlyOwner {
        uint bal = _token.balanceOf(address(this));
        require(bal != 0, "no tokens to withdraw");

        _token.safeTransfer(msg.sender, bal);
    }

    function withdrawETH() public onlyOwner {
        uint bal = address(this).balance;
        require(bal != 0, "no eth to withdraw");

        payable(msg.sender).transfer(bal);
    }
}

