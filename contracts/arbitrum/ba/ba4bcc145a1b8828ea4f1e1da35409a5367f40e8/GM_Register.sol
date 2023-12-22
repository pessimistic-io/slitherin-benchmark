pragma solidity ^0.8.17;
import "./Ownable.sol";
import "./IERC20.sol";
import "./ERC20.sol";
import "./IERC721.sol";
import "./ReentrancyGuard.sol";
import "./Utils.sol";

interface IFren {
    function balanceOf(address) external view returns (uint256);

    function transfer(address to, uint256 amount) external returns (bool);
}

contract GM_Alloc_Registation is Ownable, ReentrancyGuard {
    struct FrenInfo {
        uint256 GMamount; // current GM Count
        uint256 NFABalance; // current $NFA Balance
        uint256 NFTBalance; // current $NFA NFT Balance
        uint256 FrenTier; //User FrenTier
        uint256 registerTime; //unix timestamp for the register
    }

    mapping(address => FrenInfo) public frenInfo;
    mapping(address => uint256) public frenGMreward;
    mapping(address => bool) public _hasregisted;
    mapping(address => bool) public _claimed;
    mapping(address => bool) public _isNonFren;
    mapping(uint256 => IERC20) public lpTokens;
    uint256 public decimals = 10 ** 18;
    uint256 public adjust = 1;
    uint256 public div = 100;
    uint256 public registerFee = 0;
    bool public ClaimEnabled = false;

    uint public PLEB = 0;

    uint256 public MaxPlebStat = 100000 * decimals;
    uint256 public PLEB_Reward = 690 * decimals;
    uint256 public NFAPLEB_amount = 10_000 * decimals;
    uint256 public NFTPLEB_amount = 1;
    uint public FREN = 1;
    uint256 public MaxFrenStat = 757614 * decimals;
    uint256 public FREN_Reward = 3150 * decimals;
    uint256 public NFAFREN_amount = 100_000 * decimals;
    uint256 public NFTFREN_amount = 2;
    uint public GUDFREN = 2;
    uint256 public GUDFREN_Reward = 6300 * decimals;
    uint256 public MaxGudFrenStat = 2328000 * decimals;
    uint256 public NFAGUDFREN_amount = 420_000 * decimals;
    uint256 public NFTGUDFREN_amount = 3;
    uint public CHADFREN = 3;
    uint256 public CHADFREN_Reward = 12600 * decimals;
    uint256 public MaxChadStat = 109118550 * decimals;
    uint256 public NFACHAD_amount = 1_000_000 * decimals;
    uint256 public NFTCHAD_amount = 5;
    GM frensGM;
    address public NFA_ERC721 = 0x249bB0B4024221f09d70622444e67114259Eb7e8;
    address public NFA_ERC20 = 0x54cfe852BEc4FA9E431Ec4aE762C33a6dCfcd179;
    address public wGM_ERC20 = 0x54cfe852BEc4FA9E431Ec4aE762C33a6dCfcd179;
    event Registered(address indexed account, uint256 frenTier);
    event Claimed(address indexed account, uint256 gmAmount);

    constructor() public {
        frensGM = GM(NFA_ERC721);
    }

    function register() public {
        require(!_hasregisted[msg.sender], "Fren Already registed");
        require(!_isNonFren[msg.sender], "NonFrens not Allowed");
        uint256 gmAmount = frensGM.user_GM(msg.sender);
        uint256 NFABalance = IFren(NFA_ERC20).balanceOf(msg.sender);
        uint256 NFTBalance = IFren(NFA_ERC721).balanceOf(msg.sender);
        uint256 FrenStat = NFABalance * NFTBalance;

        FrenInfo memory fren = frenInfo[msg.sender];

        fren.GMamount = gmAmount;
        fren.NFABalance = NFABalance;
        fren.NFTBalance = NFTBalance;
        fren.registerTime = block.timestamp;

        if (NFABalance >= NFACHAD_amount && NFTBalance >= NFTCHAD_amount) {
            uint256 reward = (CHADFREN_Reward * FrenStat) / MaxChadStat;
            fren.FrenTier = CHADFREN;
            if (reward > CHADFREN_Reward) {
                frenGMreward[msg.sender] = CHADFREN_Reward;
            } else {
                frenGMreward[msg.sender] = (CHADFREN_Reward * FrenStat) / MaxChadStat;
            }
        } else if (NFABalance >= NFAGUDFREN_amount && NFTBalance >= NFTGUDFREN_amount) {
            uint256 reward = (GUDFREN_Reward * FrenStat) / MaxGudFrenStat;
            fren.FrenTier = GUDFREN;
            if (reward > GUDFREN_Reward) {
                frenGMreward[msg.sender] = GUDFREN_Reward;
            } else {
                frenGMreward[msg.sender] = (GUDFREN_Reward * FrenStat) / MaxGudFrenStat;
            }
        } else if (NFABalance >= NFAFREN_amount && NFTBalance >= NFTFREN_amount) {
            uint256 reward = (FREN_Reward * FrenStat) / MaxFrenStat;
            fren.FrenTier = FREN;

            if (reward > FREN_Reward) {
                frenGMreward[msg.sender] = FREN_Reward;
            } else {
                frenGMreward[msg.sender] = (FREN_Reward * FrenStat) / MaxFrenStat;
            }
        } else if (NFABalance >= NFAPLEB_amount && NFTBalance >= NFTPLEB_amount) {
            uint256 reward = (PLEB_Reward * FrenStat) / MaxPlebStat;
            fren.FrenTier = PLEB;

            if (reward > PLEB_Reward) {
                frenGMreward[msg.sender] = PLEB_Reward;
            } else {
                frenGMreward[msg.sender] = (PLEB_Reward * FrenStat) / MaxPlebStat;
            }
        }

        emit Registered(msg.sender, fren.FrenTier);
    }

    function GM_reward(address _fren) public view returns (uint256) {
        uint256 NFABalance = IFren(NFA_ERC20).balanceOf(_fren);
        uint256 NFTBalance = IFren(NFA_ERC721).balanceOf(_fren);
        uint256 FrenStat = NFABalance * NFTBalance;

        if (NFABalance >= NFACHAD_amount && NFTBalance >= NFTCHAD_amount) {
            uint256 reward = (CHADFREN_Reward * FrenStat) / MaxChadStat;
            if (reward > CHADFREN_Reward) {
                return CHADFREN_Reward;
            } else {
                return (CHADFREN_Reward * FrenStat) / MaxChadStat;
            }
        } else if (NFABalance >= NFAGUDFREN_amount && NFTBalance >= NFTGUDFREN_amount) {
            uint256 reward = (GUDFREN_Reward * FrenStat) / MaxGudFrenStat;
            if (reward > GUDFREN_Reward) {
                return GUDFREN_Reward;
            } else {
                return (GUDFREN_Reward * FrenStat) / MaxGudFrenStat;
            }
        } else if (NFABalance >= NFAFREN_amount && NFTBalance >= NFTFREN_amount) {
            uint256 reward = (FREN_Reward * FrenStat) / MaxFrenStat;
            if (reward > FREN_Reward) {
                return FREN_Reward;
            } else {
                return (FREN_Reward * FrenStat) / MaxFrenStat;
            }
        } else if (NFABalance >= NFAPLEB_amount && NFTBalance >= NFTPLEB_amount) {
            uint256 reward = (PLEB_Reward * FrenStat) / MaxPlebStat;
            if (reward > PLEB_Reward) {
                return PLEB_Reward;
            } else {
                return (PLEB_Reward * FrenStat) / MaxPlebStat;
            }
        }
    }

    function claimWGM() public nonReentrant returns (uint256) {
        require(ClaimEnabled, "Claim hasnt Started Fren");
        require(!_claimed[msg.sender], "Fren Already claimed");
        require(!_isNonFren[msg.sender], "NonFrens not Allowed");
        uint256 gmCount = frensGM.user_GM(msg.sender);
        uint256 wGM_amount = (frenGMreward[msg.sender] * gmCount) / div;
        _claimed[msg.sender] = true;
        IFren(wGM_ERC20).transfer(msg.sender, wGM_amount);

        emit Claimed(msg.sender, wGM_amount);
    }

    function setNonFrens(address[] calldata _addresses, bool bot) public onlyOwner {
        for (uint256 i = 0; i < _addresses.length; i++) {
            _isNonFren[_addresses[i]] = bot;
        }
    }

    function changeGM(address _gm, uint256 _div) external onlyOwner {
        frensGM = GM(_gm);
        div = _div;
    }

    function changeWGM(address _wgm) external onlyOwner {
        wGM_ERC20 = _wgm;
    }

    function toggleClaim() external onlyOwner {
        ClaimEnabled = !ClaimEnabled;
    }

    function changeMaxStatConstants(
        uint256 _MaxChadStat,
        uint256 _MaxPlebStat,
        uint256 _MaxFrenStat,
        uint256 _MaxGudFrenStat
    ) external onlyOwner {
        MaxChadStat = _MaxChadStat;
        MaxPlebStat = _MaxPlebStat;
        MaxFrenStat = _MaxFrenStat;
        MaxGudFrenStat = _MaxGudFrenStat;
    }

    function changeRewardConstants(
        uint256 _GUDFREN_Reward,
        uint256 _FREN_Reward,
        uint256 _PLEB_Reward,
        uint256 _CHADFREN_Reward
    ) external onlyOwner {
        PLEB_Reward = _PLEB_Reward;
        FREN_Reward = _FREN_Reward;
        GUDFREN_Reward = _GUDFREN_Reward;
        CHADFREN_Reward = _CHADFREN_Reward;
    }
}

