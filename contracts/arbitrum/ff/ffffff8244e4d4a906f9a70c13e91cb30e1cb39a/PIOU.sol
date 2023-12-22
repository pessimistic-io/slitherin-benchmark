// SPDX-License-Identifier: MIT
pragma solidity ^0.8.13;
import "./MerkleProof.sol";

import {ERC20} from "./ERC20.sol";
import {SafeTransferLib} from "./SafeTransferLib.sol";
import {Ownable} from "./Ownable.sol";

contract PIOU is ERC20("PIOU", "P*** IOU Token", 18), Ownable {
    ////////////////////////////////////////////////////////////////////// libraries
    using SafeTransferLib for ERC20;
    ////////////////////////////////////////////////////////////////////// state
    enum State {
        Active,
        Paused,
        Ended
    }
    State public state = State.Paused;

    modifier onlyActive() {
        require(state == State.Active, "not active");
        _;
    }

    function unpause() external onlyOwner {
        require(state == State.Paused, "not paused");
        state = State.Active;
    }

    function pause() external onlyOwner onlyActive {
        state = State.Paused;
    }

    function end() external onlyOwner {
        state = State.Ended;
    }

    ////////////////////////////////////////////////////////////////////// merkle tree
    bytes32 public merkleRoot;
    event MerkleRootChanged(bytes32 _merkleRoot);

    ////////////////////////////////////////////////////////////////////// claim stable
    ERC20 public immutable asset;
    address public treasury = address(0);
    uint256 public stableSwapRate = 746; // 746k USDC to dissolve
    event TreasuryAddressChanged(address _treasury);
    event StableSwapRateChanged(uint256 _stableSwapRate);
    event ClaimStable(
        address indexed account,
        uint256 amount,
        uint256 amountStable
    );

    ////////////////////////////////////////////////////////////////////// claim token
    event Claim(address indexed account, uint256 amount);

    ////////////////////////////////////////////////////////////////////// data
    uint256 public totalExited;
    uint256 public totalMigrated;
    mapping(address => uint256) public claimedByAddress;

    //////////////////////////////////////////////////////////////////////
    constructor(
        bytes32 _merkleRoot,
        address _owner,
        address _treasury,
        ERC20 _asset
    ) {
        merkleRoot = _merkleRoot;
        treasury = _treasury;
        asset = _asset;
        transferOwnership(_owner);
    }

    ////////////////////////////////////////////////////////////////////// merkle tree
    function _leaf(address account, uint256 allocation)
        public
        pure
        returns (bytes32)
    {
        return keccak256(abi.encodePacked(account, ",", allocation));
    }

    function _verify(
        address account,
        uint256 allocation,
        bytes32[] calldata merkleProof
    ) public view returns (bool) {
        bool isValid = MerkleProof.verify(
            merkleProof,
            merkleRoot,
            _leaf(account, allocation)
        );
        return isValid;
    }

    ////////////////////////////////////////////////////////////////////// read
    function totalClaimed() public view returns (uint256) {
        return totalExited + totalMigrated;
    }

    function previewClaim(uint256 _claimable) public pure returns (uint256) {
        return ((_claimable * 10**18) / 5);
    }

    function previewClaimStable(uint256 _claimable)
        public
        view
        returns (uint256)
    {
        return (_claimable * stableSwapRate);
    }

    ////////////////////////////////////////////////////////////////////// public

    function claim(
        address _to,
        uint256 _allocation,
        bytes32[] calldata merkleProof
    ) external onlyActive {
        // Verify the merkle proof.
        require(
            _verify(msg.sender, _allocation, merkleProof),
            "Merkle Tree: Invalid proof."
        );
        require(
            claimedByAddress[msg.sender] < _allocation,
            "Merkle Tree: Already claimed."
        );
        uint256 claimable = _allocation - claimedByAddress[msg.sender];

        // Mark it claimed and send the token.
        totalMigrated += claimable;
        claimedByAddress[msg.sender] += claimable;
        _mint(_to, previewClaim(claimable));
        emit Claim(_to, claimable);
    }

    function claimStable(
        address _to,
        uint256 _allocation,
        bytes32[] calldata merkleProof
    ) external onlyActive {
        // Verify the merkle proof.
        require(
            _verify(msg.sender, _allocation, merkleProof),
            "Merkle Tree: Invalid proof."
        );
        require(
            claimedByAddress[msg.sender] < _allocation,
            "Merkle Tree: Already claimed."
        );

        uint256 claimable = _allocation - claimedByAddress[msg.sender];
        uint256 amount = previewClaimStable(claimable);
        require(
            asset.allowance(treasury, address(this)) >= amount,
            "Not enough allowance in treasury"
        );

        // Mark it claimed and send the token.
        totalExited += claimable;
        claimedByAddress[msg.sender] += claimable;

        asset.safeTransferFrom(treasury, _to, amount);
        emit ClaimStable(_to, claimable, amount);
    }

    ////////////////////////////////////////////////////////////////////// admin
    function setStableSwapRate(uint256 _stableSwapRate) external onlyOwner {
        stableSwapRate = _stableSwapRate;
        emit StableSwapRateChanged(_stableSwapRate);
    }

    function setMerkleRoot(bytes32 _merkleRoot) external onlyOwner {
        merkleRoot = _merkleRoot;
        emit MerkleRootChanged(_merkleRoot);
    }

    function setTreasuryAddress(address _treasury) external onlyOwner {
        treasury = _treasury;
        emit TreasuryAddressChanged(_treasury);
    }
}

