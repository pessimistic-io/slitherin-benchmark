// SPDX-License-Identifier: MIT
pragma solidity 0.6.12;
import {MintableBaseToken} from "./MintableBaseToken.sol";
import {SafeMath} from "./SafeMath.sol";
import {IERC20} from "./IERC20.sol";
import {SafeERC20} from "./SafeERC20.sol";
import {ReentrancyGuardUpgradeable} from "./ReentrancyGuardUpgradeable.sol";
import {OwnableUpgradeable} from "./OwnableUpgradeable.sol";
import {Initializable} from "./Initializable.sol";
import {IBurner} from "./IBurner.sol";

contract InstantVester is Initializable, ReentrancyGuardUpgradeable, OwnableUpgradeable {
    using SafeMath for uint256;
    using SafeERC20 for IERC20;

    MintableBaseToken public claimToken;
    MintableBaseToken public depositToken;

    address[] public receivers;
    uint256 public vestedForUser;

    uint256 public claimWeight;
    uint256 public burnWeight;

    address public treasury;
    uint256 public treasuryWeight;

    IBurner public burner;

    uint256 public totalClaimed;
    uint256 public totalDeposited;
    uint256 public totalBurned;
    uint256 public totalTreasury;

    mapping(address => uint256) public accountTotalClaimed;
    mapping(address => uint256) public accountTotalDeposited;
    mapping(address => uint256) public accountTotalBurned;
    mapping(address => uint256) public accountTotalTreasury;

    mapping(address => bool) public isHandler;


    event InstantVest(
        address account,
        uint256 depositAmount,
        uint256 claimAmount,
        uint256 burnAmount,
        uint256 treasuryAmount
    );
    function initialize(
        MintableBaseToken _depositToken,
        MintableBaseToken _claimToken,
        uint256 _claimWeight,
        uint256 _burnWeight,
        address _treasury,
        uint256 _treasuryWeight,
        IBurner _burner
    ) public initializer {
        claimWeight = _claimWeight;
        burnWeight = _burnWeight;

        uint totalDistribution = uint(1e18).sub(_burnWeight).sub(_claimWeight).sub(_treasuryWeight);
        require(totalDistribution == 0, 'InstantVester: Total distribution not 100%');

        depositToken = _depositToken;
        claimToken = _claimToken;

        treasury = _treasury;
        treasuryWeight = _treasuryWeight;
        burner = _burner;

        __Ownable_init();
        __ReentrancyGuard_init();
    }
    function setTreasuryWeight(uint256 _weight) public onlyOwner {
        treasuryWeight = _weight;
    }

    function setBurnWeight(uint256 _weight) public onlyOwner {
        burnWeight = _weight;
    }

    function setClaimWeight(uint256 _weight) public onlyOwner {
        claimWeight = _weight;
    }

    function withdraw(uint256 amount) public onlyOwner {
        // only owner can withdraw tokens directly
        IERC20(claimToken).safeTransfer(msg.sender, amount);
    }

    function getProportion(uint256 amount, uint256 percentage) public pure returns (uint) {
        return amount.mul(percentage).div(1e18);
    }
    function setHandler(address _handler, bool _isActive) public onlyOwner {
        isHandler[_handler] = _isActive;
    }

    function validatePermissions() public view {
        require(
            MintableBaseToken(depositToken).isHandler(address(this)),
            'Instant vester is not a handler and cannot transfer'
        );
    }

    function instantVest(uint256 amount) public nonReentrant {
        _instantVestForAccount(msg.sender, amount);
    }

    function instantVestForAccount(address account, uint256 amount) public onlyHandler nonReentrant {
        _instantVestForAccount(account, amount);
    }

    function _updateStats(address account, uint depositAmount, uint claimAmount, uint burnAmount, uint treasuryAmount) private {
        // tracking stats
        totalClaimed = totalClaimed.add(claimAmount);
        accountTotalClaimed[account] = accountTotalClaimed[account].add(claimAmount);

        totalDeposited = totalDeposited.add(depositAmount);
        accountTotalDeposited[account] = accountTotalDeposited[account].add(depositAmount);
        totalBurned = totalBurned.add(burnAmount);
        accountTotalBurned[account] = accountTotalBurned[account].add(burnAmount);

        totalTreasury = totalTreasury.add(treasuryAmount);
        accountTotalTreasury[account] = accountTotalTreasury[account].add(treasuryAmount);
    }

    function _instantVestForAccount(address account, uint256 depositAmount) private {
        require(account != address(0), 'InstantVester: Invalid address');
        require(depositToken.balanceOf(account) >= depositAmount, 'InstantVester: amount exceeds balance');
        uint claimAmount = getProportion(depositAmount, claimWeight);
        require(claimToken.balanceOf(address(this)) >= claimAmount, 'InstantVester: Insufficient vester balance');

        // burn all the esTND
        depositToken.transferFrom(account, address(this), depositAmount);
        burner.transferAndBurn(address(depositToken), depositAmount);

        // send TND to dao treasury
        uint treasuryAmount = getProportion(depositAmount, treasuryWeight);
        claimToken.transfer(treasury, treasuryAmount);

        // send TND to secure burn contract
        uint burnAmount = getProportion(depositAmount, burnWeight);
        claimToken.approve(address(burner), burnAmount);
        burner.transferAndBurn(address(claimToken), burnAmount);

        // identity property of addition
        require(
            claimAmount.add(treasuryAmount) == depositAmount.sub(burnAmount),
            'Error total burn, treasury, and claim do not match deposit amount'
        );

        // send TND to caller
        claimToken.transfer(account, claimAmount);
        _updateStats(account, depositAmount, claimAmount, burnAmount, treasuryAmount);
        emit InstantVest(
            account,
            depositAmount,
            claimAmount,
            burnAmount,
            treasuryAmount
        );
    }

    modifier onlyHandler() {
        require(isHandler[msg.sender], "MintableBaseToken: forbidden");
        _;
    }
}



