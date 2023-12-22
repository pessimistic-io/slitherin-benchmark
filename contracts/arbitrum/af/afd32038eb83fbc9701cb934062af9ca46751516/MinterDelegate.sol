// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "./MerkleProof.sol";
import "./TinyOwnable.sol";
import "./Recoverable.sol";

abstract contract Security {
    modifier onlySender() {
        require(tx.origin == msg.sender, "The caller is another contract");
        _;
    }
}

interface IMint {
    function delegateMint(address _addr, uint256 amount) external;
}

contract MinterDelegate is Security, Ownable, Recoverable {
    IMint public targetContract;

    uint256 public maxMint = 4300;
    uint256 public totalMinted;
    uint256 public cost = 40000000000000000;
    uint256 public costWl = 36000000000000000;
    bytes32 public root;
    bool public publicMintIsActive;
    bool public WlMintIsActive;

    mapping(address => bool) public wlMinter;

    event Mint(string eventName, address sender, uint256 amount);

    function _mint(address addr, uint256 amount) internal {
        targetContract.delegateMint(addr, amount);
        emit Mint("Mint", addr, amount);
    }

    function airdrop(address addr, uint256 amount) external onlyOwner {
        _mint(addr, amount);
    }

    function mintWl(bytes32[] memory proof) external payable onlySender {
        require(WlMintIsActive, "Whitelist mint paused");
        require(msg.value >= costWl, "Not enough eth");
        require(!wlMinter[msg.sender], "Already minted");
        require(
            totalMinted + 1 <= maxMint,
            "Max supply exceeded for this phase"
        );

        bytes32 leaf = keccak256(
            bytes.concat(keccak256(abi.encode(msg.sender)))
        );
        require(MerkleProof.verify(proof, root, leaf), "Invalid proof");
        targetContract.delegateMint(msg.sender, 1);
        wlMinter[msg.sender] = true;
        totalMinted += 1;
    }

    function mintPublic(uint256 qty) external payable onlySender {
        require(publicMintIsActive, "Mint paused");
        require(msg.value >= cost * qty, "Not enough eth");
        require(totalMinted + qty <= maxMint, "Max supply exceeded");

        targetContract.delegateMint(msg.sender, qty);
        totalMinted += qty;
    }

    function setContract(address _contract) external onlyOwner {
        targetContract = IMint(_contract);
    }

    function setRoot(bytes32 _root) external onlyOwner {
        root = _root;
    }

    function setCost(uint256 _cost) external onlyOwner {
        cost = _cost;
    }

    function setCostWl(uint256 _costWl) external onlyOwner {
        costWl = _costWl;
    }

    function setMaxMint(uint256 _maxMint) external onlyOwner {
        maxMint = _maxMint;
    }

    function toggleWlSale() public onlyOwner {
        WlMintIsActive = !WlMintIsActive;
    }

    function togglePublicSale() public onlyOwner {
        publicMintIsActive = !publicMintIsActive;
    }
}

