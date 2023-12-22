pragma solidity = 0.8.14;

import "./MerkleProof.sol";
import "./Ownable.sol";
import "./IERC20.sol";

//--- Contract v2 ---//
contract LBPGWOMint is Ownable {
    address public LBPGWO = 0x8194c46b3288A086C4f19E1361C978e3cD58B6c3;
    mapping(address => uint256) public usermint;
    mapping(address => bool) public userclaim;
    uint256 public userClaimedAmount;
    bytes32 private _merkleRoot = 0xae92f88c3e2ad76498d1526607eb1fdbd0add8036101e06a97ddfc980dc489fc;
    uint256 public MaxClaimAmount = 30000;
    uint256 public SingleClaimAmount = 3_362_000 * 10 ** 9;
    uint256 public SingleMintAmount = 353_010_000_000 * 10 ** 9;
    uint256 public LBPGWOmintPrice = 0.0001 ether;
    bool public IsCanMint = true;
    bool public IsCanClaim;

    constructor () {}

    modifier callerIsUser() {
        require(tx.origin == msg.sender, "Must from real wallet address");
        _;
    }

    function mintLBPGWO(uint256 _quantity) external payable  {
        require(IsCanMint, "Not in the claim stage.");
        require(IERC20(LBPGWO).balanceOf(address(this)) > 0, "mint has ended.");
        require(usermint[msg.sender] + _quantity <= 200, "Invalid quantity");
        require(msg.value >= _quantity * LBPGWOmintPrice, "Ether is not enough");
        usermint[msg.sender] += _quantity;
        IERC20(LBPGWO).transfer(msg.sender, _quantity * SingleMintAmount);
    }

    function claimLBPGWO(bytes32[] calldata _merkleProof) external payable callerIsUser  {
        require(isWhitelistAddress(msg.sender, _merkleProof), "Caller is not in whitelist or invalid signature");
        require(IsCanClaim, "Not in the claim stage.");
        require(IERC20(LBPGWO).balanceOf(address(this)) > 0, "claim has ended.");
        require(!userclaim[msg.sender], "Invalid quantity");
        require(userClaimedAmount + 1 <= MaxClaimAmount, "Invalid quantity");
        userclaim[msg.sender] = true;
        userClaimedAmount++;
        IERC20(LBPGWO).transfer(msg.sender, SingleClaimAmount);
    }

    function isWhitelistAddress(address _address, bytes32[] calldata _signature) public view returns (bool) {
        return MerkleProof.verify(_signature, _merkleRoot, keccak256(abi.encodePacked(_address)));
    }

    receive() external payable {}


    function changeLBPGWOmintPrice(uint256 LBPGWOmintPrice_) external onlyOwner {
        LBPGWOmintPrice = LBPGWOmintPrice_;
    }

    function changeSingleMintAmount(uint256 SingleMintAmount_) external onlyOwner {
        SingleMintAmount = SingleMintAmount_;
    }

    function changeIsCanClaim(bool IsCanClaim_) external onlyOwner {
        IsCanClaim = IsCanClaim_;
    }

    function changeIsCanMint(bool IsCanMint_) external onlyOwner {
        IsCanMint = IsCanMint_;
    }

    function changeLBPGWO(address LBPGWO_) external onlyOwner {
        LBPGWO = LBPGWO_;
    }

    function changeMaxClaimAmount(uint256 MaxClaimAmount_) external onlyOwner {
        MaxClaimAmount = MaxClaimAmount_;
    }

    function changeSingleClaimAmount(uint256 SingleClaimAmount_) external onlyOwner {
        SingleClaimAmount = SingleClaimAmount_;
    }

    function setMerkleRoot(bytes32 merkleRoot) external onlyOwner {
        _merkleRoot = merkleRoot;
    }

    function withdrawEth() external payable onlyOwner {
        (bool success,) = msg.sender.call{value : address(this).balance}("");
        require(success, "Transfer failed.");
    }

    function withdrawToken() external payable onlyOwner {
        uint256 selfbalance = IERC20(LBPGWO).balanceOf(address(this));
        if (selfbalance > 0) {
            bool success =  IERC20(LBPGWO).transfer(msg.sender, selfbalance);
            require(success, "payMent  Transfer failed.");
        }
    }

}
