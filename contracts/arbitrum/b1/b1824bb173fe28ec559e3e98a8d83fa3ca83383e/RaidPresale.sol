pragma solidity 0.8.7;

import "./IERC20.sol";
import "./IUniswapV2Router02.sol";
import "./MerkleProof.sol";

contract RaidPresale {
    address public immutable owner;
    uint256 public startTime;
    uint256 public endTime;

    mapping(address => uint256) public amountPurchased;
    uint256 public immutable maxPerWallet = 0.001 ether;
    uint256 public immutable maxPerWhitelistWallet = 0.003 ether;
    uint256 public presalePrice = 8000 * 1e18;
    uint256 public totalPurchased = 0;
    uint256 public presaleMax = 150 ether;
    uint256 public BASIS_POINT = 100;
    bool public liquidityAdded;
    mapping(address => RefDetail) public refDetails;
    struct RefDetail{
        uint256 refCount;
        uint256 refReward;
    }

    address public immutable RAID;
    address public immutable CAMELOT_ROUTER = 0x9Ac64Cc6e4415144C455BD8E4837Fea55603e5c3;//Pancakeswap in testnet, Camelot in mainnet

    /**
     * @notice Merkle root hash for whitelist addresses
     */
    bytes32 public merkleRoot;
    constructor(uint256 _startTime, address _RAID) {
        owner = msg.sender;
        startTime = _startTime;
        endTime = _startTime + 10 days;
        RAID = _RAID;
    }

    modifier onlyOwner {
        require(owner == msg.sender);
        _;
    }
    function setStartAndEndTime(uint256 _newStartTime, uint256 _newEndTime) external onlyOwner{
        require(_newEndTime > _newStartTime, "End time must be after start time");
        startTime = _newStartTime;
        endTime = _newEndTime;
    }
    function setPresalePrice(uint256 _newPrice) external onlyOwner{
        presalePrice = _newPrice;
    }
    function setHardCap(uint256 _max) external onlyOwner{
        presaleMax = _max;
    }

    function setMerkleRoot(bytes32 merkleRootHash) external onlyOwner {
        merkleRoot = merkleRootHash;
    }
    function getPendingRaid(address _address) public view returns(uint256) {
        return (amountPurchased[_address] * presalePrice / 1e18) + refDetails[_address].refReward;
    }

    function isWhitelistWinner(
        bytes32[] calldata _merkleProof,
        address _user
    ) public view returns (bool) {
        bytes32 leaf = keccak256(abi.encodePacked(_user));
        return MerkleProof.verify(_merkleProof, merkleRoot, leaf);
    }

    function buyPresale(address ref, bytes32[] calldata _merkleProof) external payable {
        require(block.timestamp >= startTime && block.timestamp <= endTime, "Not active");
        require(msg.sender == tx.origin, "No contracts");
        require(msg.value > 0, "Zero amount");
        if(isWhitelistWinner(_merkleProof, msg.sender)){
            require(amountPurchased[msg.sender] + msg.value <= maxPerWhitelistWallet, "Over whitelist wallet limit");
        }else{
            require(amountPurchased[msg.sender] + msg.value <= maxPerWallet, "Over wallet limit");
        }
        require(totalPurchased + msg.value <= presaleMax, "Reached presale limit");
        if(ref != address(0) && amountPurchased[ref] > 0){
            refDetails[ref].refCount++;
            refDetails[ref].refReward += (msg.value * presalePrice / 1e18) * 1 / BASIS_POINT;
            refDetails[msg.sender].refReward += (msg.value * presalePrice / 1e18) * 1 / BASIS_POINT;
        }
        amountPurchased[msg.sender] += msg.value;
        totalPurchased += msg.value;
    }

    function claim() external {
        require(!liquidityAdded, "Presale not ended yet");
        require(amountPurchased[msg.sender] > 0, "No amount claimable");
        uint256 amount = getPendingRaid(msg.sender);
        amountPurchased[msg.sender] = 0;
        IERC20(RAID).transfer(msg.sender, amount);
    }

    function setMax(uint256 _max) external onlyOwner {
        presaleMax = _max;
    }

    function addLiquidity() external onlyOwner {
        require(block.timestamp > endTime, "Not finished");
        IERC20(RAID).approve(CAMELOT_ROUTER, type(uint256).max);
        uint256 totalAmount = address(this).balance;
        (bool success,) = owner.call{value: totalAmount * 20 / BASIS_POINT}("");
        require(success);
        uint256 ethAmount = totalAmount - (totalAmount * 20 / BASIS_POINT);
        uint256 tokenAmount = (ethAmount * presalePrice / 1e18) * 70 / BASIS_POINT;
        IUniswapV2Router02(CAMELOT_ROUTER).addLiquidityETH{value: ethAmount}(
            RAID,
            tokenAmount,
            1,
            1,
            0x000000000000000000000000000000000000dEaD,
            type(uint256).max
        );
        liquidityAdded = true;
    }
}
