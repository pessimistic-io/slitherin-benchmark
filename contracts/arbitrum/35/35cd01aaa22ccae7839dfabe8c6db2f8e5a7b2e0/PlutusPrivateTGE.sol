// SPDX-License-Identifier: MIT
pragma solidity ^0.8.11;
import "./MerkleProof.sol";

contract PlutusPrivateTGE {
    bytes32 public merkleRoot;
    address public governance;
    address public deployer;
    address public proposedGovernance;
    uint256 public accountCap;
    uint256 public raiseCap;
    bool public started = false;
    uint256 raisedAmount;

    mapping(address => uint256) public deposit;

    event TGEStart();
    event Contribute(address indexed user, uint256 amt);
    event WhitelistUpdate();
    event GovernanceWithdraw(address indexed to, uint256 amt);
    event GovernancePropose(address indexed newAddr);
    event GovernanceChange(address indexed from, address indexed to);

    constructor(
        address _deployer,
        address _governance,
        bytes32 _merkleRoot
    ) {
        deployer = _deployer;
        governance = _governance;
        merkleRoot = _merkleRoot;
        accountCap = 0.5 ether;
        started = false;
    }

    function isOnAllowList(bytes32[] calldata _merkleProof)
        internal
        view
        returns (bool)
    {
        bytes32 leaf = keccak256((abi.encodePacked((msg.sender))));
        return MerkleProof.verify(_merkleProof, merkleRoot, leaf);
    }

    function contribute(bytes32[] calldata _merkleProof) external payable {
        require(started == true, "Soon");
        require(isOnAllowList(_merkleProof), "Sender not on allowlist");
        require(
            msg.value + raisedAmount <= raiseCap,
            "TGE total limit exceeded"
        );
        require(
            deposit[msg.sender] + msg.value <= accountCap,
            "Individual contribution limit exceeded"
        );
        deposit[msg.sender] += msg.value;
        raisedAmount += msg.value;

        emit Contribute(msg.sender, msg.value);
    }

    function details()
        external
        view
        returns (
            bool,
            uint256,
            uint256,
            uint256,
            uint256,
            uint256
        )
    {
        return (
            started,
            address(msg.sender).balance,
            raisedAmount,
            raiseCap,
            deposit[msg.sender],
            accountCap
        );
    }

    /** MODIFIERS */
    modifier onlyDeployerOrGovernance() {
        require(
            msg.sender == governance || msg.sender == deployer,
            "Unauthorized"
        );
        _;
    }

    modifier onlyGovernance() {
        require(msg.sender == governance, "Unauthorized");
        _;
    }

    modifier onlyProposedGovernance() {
        require(msg.sender == proposedGovernance, "Unauthorized");
        _;
    }

    /** GOVERNANCE FUNCTIONS */
    function setMerkleRoot(bytes32 _merkleRoot)
        external
        onlyDeployerOrGovernance
    {
        merkleRoot = _merkleRoot;
        emit WhitelistUpdate();
    }

    function setAccountCapInWEI(uint256 _cap)
        external
        onlyDeployerOrGovernance
    {
        accountCap = _cap;
    }

    function setRaiseCapInETH(uint256 _cap) external onlyDeployerOrGovernance {
        raiseCap = _cap * 1e18;
    }

    function setStarted(bool _started) external onlyDeployerOrGovernance {
        require(raiseCap > 0, "TGE cap cannot be zero");
        started = _started;
        emit TGEStart();
    }

    function governanceWithdrawAll() external onlyGovernance {
        uint256 amt = address(this).balance;
        payable(governance).transfer(address(this).balance);
        emit GovernanceWithdraw(governance, amt);
    }

    function proposeGovernance(address _proposedGovernanceAddr)
        external
        onlyGovernance
    {
        require(_proposedGovernanceAddr != address(0));
        proposedGovernance = _proposedGovernanceAddr;
        emit GovernancePropose(_proposedGovernanceAddr);
    }

    function claimGovernance() external onlyProposedGovernance {
        address oldGovernance = governance;
        governance = proposedGovernance;
        proposedGovernance = address(0);
        emit GovernanceChange(oldGovernance, governance);
    }
}

