//SPDX-License-Identifier: MIT
pragma solidity ^0.8.9;

import "./IA3SToken.sol";
import "./ERC20.sol";
import "./Ownable.sol";

contract A3SToken is IA3SToken, ERC20, Ownable {
    uint256 public total_maxSupply = 1 * (10**9) * (10**18);

    uint256 public total_q2earnSupply = total_maxSupply * 90 / 100; // 90% of total max supply is used for queue to earn gaming

    uint256 public total_TreasurySupply = total_maxSupply * 95 / 1000; // 9.5% of total max supply is used for treasury 
    uint256 public initial_TreasurySupply = total_TreasurySupply * 10 / 100;
    uint256 public continue_TreasurySupply = total_TreasurySupply * 15 / 100; // every 6 month for 3 yrs
    
    uint256 public total_ProjectPartySupply = total_maxSupply * 5 / 1000; // 0.5% of total max supply is used for project 
    uint256 public initial_ProjectPartySupply = total_ProjectPartySupply * 10 / 100;
    uint256 public continue_ProjectPartySupply = total_ProjectPartySupply * 1125 / 10000 ; // every 6 month for 4 yrs

    address A3STreasury;
    address A3SProjectParty;

    mapping(address => bool) public governors;
    address bridge;

    uint256 public startTimestamp;
    uint256 public lastMint_Treasury;
    uint256 public lastMint_Project;
    uint256 public queue2earnSupply;
    uint256 public treasurySupply;
    uint256 public projectSupply;
    uint256 public mintGap; // In Seconds, For testing purpose, gap is 2 mins, actually should be 6 months

    event Mint(address to, uint256 amount);
    event Burn(address account, uint256 amount);
    event UpdateGovernors(address newGovernor, bool status);

    modifier ONLY_GOV() {
        require(governors[msg.sender], "A3S: caller is not governor");
        _;
    }

    modifier onlyBridge() {
        require(msg.sender == bridge, "A3S: not bridge");
        _;
    }

    constructor(
        string memory _name,
        string memory _symbol,
        address _A3STreasury,
        address _A3SProjectParty,
        uint256 _mintGap
    ) ERC20(_name, _symbol) {
        A3STreasury = _A3STreasury;
        A3SProjectParty = _A3SProjectParty;
        governors[msg.sender] = true;
        governors[A3STreasury] = true;
        governors[A3SProjectParty] = true;
        mintGap = _mintGap;
        _mint(A3STreasury, initial_TreasurySupply);
        _mint(A3SProjectParty, initial_ProjectPartySupply);
        treasurySupply += initial_TreasurySupply;
        projectSupply += initial_ProjectPartySupply;
        startTimestamp = block.timestamp;
        lastMint_Treasury = block.timestamp;
        lastMint_Project = block.timestamp;
    }

    //Queue to Play Mint
    //ONLY Governors addresss could mint
    function mint(address to, uint256 amount) external ONLY_GOV {
        require(queue2earnSupply + amount <= total_q2earnSupply, "A3S: Queue To Earn $AA token mint exceed the maximum supply");
        _mint(to, amount);
        queue2earnSupply += amount;
        emit Mint(to, amount);
    }
    
    function mint_Treasury() external ONLY_GOV {
        require(treasurySupply + continue_TreasurySupply <= total_TreasurySupply, "A3S: Treasure $AA token mint exceed the maximum supply");
        require(block.timestamp - lastMint_Treasury >= mintGap, "A3S: not until the next Treasure Mint period");
        _mint(A3STreasury, continue_TreasurySupply);
        treasurySupply += continue_TreasurySupply;
        lastMint_Treasury = block.timestamp;
        emit Mint(A3STreasury, continue_TreasurySupply);
    }

    function mint_Project() external ONLY_GOV {
        require(projectSupply + continue_ProjectPartySupply <= total_ProjectPartySupply, "A3S: Project $AA token mint exceed the maximum supply");
        require(block.timestamp - lastMint_Project >= mintGap, "A3S: not until the next Project Mint period");
        _mint(A3SProjectParty, continue_ProjectPartySupply);
        projectSupply += continue_ProjectPartySupply;
        lastMint_Project = block.timestamp;
        emit Mint(A3SProjectParty, continue_ProjectPartySupply);
    }

    // Leave the function for future Bridge feature
    // Mint privilege is limited to Bridge contract ONLY 
    function bridgeMint(address owner, uint256 amount) external onlyBridge returns(bool) {
        _mint(owner, amount);
        return true;
    }
    function bridgeBurn(address owner, uint256 amount) external onlyBridge returns(bool) {
        _burn(owner, amount);
        return true;
    }

    function updateTotalMaxSupply(uint256 new_totalMaxSupply) public onlyOwner {
        total_maxSupply = new_totalMaxSupply;
    }

    //Update governors
    function updateGovernors(address newGovernor, bool status) public onlyOwner {
        governors[newGovernor] = status;
        emit UpdateGovernors(newGovernor, status);
    }

    function updateMintGap(uint256 new_mintGap) public onlyOwner {
        mintGap = new_mintGap;
    }

    function setBridgeAccess(address bridgeAddr) external onlyOwner {
        bridge = bridgeAddr;
    }

}

