// SPDX-License-Identifier: MIT
pragma solidity 0.8.19;

import { SafeERC20 } from "./SafeERC20.sol";
import { IERC20 } from "./ERC20.sol";
import { ERC20Upgradeable } from "./ERC20Upgradeable.sol";
import { OwnableUpgradeable } from "./OwnableUpgradeable.sol";
import { Initializable } from "./Initializable.sol";
import { ReentrancyGuardUpgradeable } from "./ReentrancyGuardUpgradeable.sol";
import { PausableUpgradeable } from "./PausableUpgradeable.sol";

import "./IRadiantStaking.sol";
import "./IMasterRadpie.sol";
import "./IMultiFeeDistribution.sol";

/// @title mDLP
/// @author Magpie Team
/// @notice mDLP is a token minted when 1 ETH/BNB deposit on Radpie, the deposit is irreversible, user will get mDLP instead.
contract mDLP is
    Initializable,
    ERC20Upgradeable,
    OwnableUpgradeable,
    ReentrancyGuardUpgradeable,
    PausableUpgradeable
{
    using SafeERC20 for IERC20;

    /* ============ State Variables ============ */

    address public rdnt;
    address public rdntDlp;
    address public radiantStaking;
    address public masterRadpie;

    uint8 constant STAKEMODE = 1;

    /* ============ Events ============ */

    event mDLPConverted(address indexed _user, uint256 _amount, uint256 _mode);
    event RadiantStakingSet(address indexed _radiantStaking);
    event NativeConverted(uint256 _amount, uint256 _liquidity);
    event DlpConverted(uint256 _amount, uint256 _liquidity);
    event RdntConverted(uint256 _amount, uint256 _liquidity);

    /* ============ Errors ============ */

    error MasterRadpieNotSet();
    error RadiantStakingNotSet();
    error InvalidAmount();
    error AddressZero();

    /* ============ Constructor ============ */

    function __mDLP_init(
        address _rdnt,
        address _rdntDlp,
        address _radiantStaking,
        address _masterRadpie
    ) public initializer {
        __ERC20_init("Magpie locked DLP", "mDLP");
        __Ownable_init();
        __ReentrancyGuard_init();
        __Pausable_init();
        rdnt = _rdnt;
        rdntDlp = _rdntDlp;
        masterRadpie = _masterRadpie;
        radiantStaking = _radiantStaking;
    }

    /* ============ External Functions ============ */

    function convertWithZapRadiant(
        address _for,
        uint256 _rdntAmt,
        uint8 _mode
    ) public payable nonReentrant whenNotPaused returns (uint256) {
        uint256 _liquidity = 0;

        if (_rdntAmt != 0) {
            IERC20(rdnt).safeTransferFrom(msg.sender, address(this), _rdntAmt);
            IERC20(rdnt).safeApprove(radiantStaking, _rdntAmt);
            _liquidity = IRadiantStaking(radiantStaking).zapRdnt{ value: msg.value }(_for,_rdntAmt);
        } else {
            _liquidity = IRadiantStaking(radiantStaking).zapNative{ value: msg.value }(_for);
        }

        _mintMDLP(_for, _liquidity, _mode);

        return _liquidity;
    }

    function convertWithLp(
        address _for,
        uint256 _amount,
        uint8 _mode
    ) external nonReentrant whenNotPaused {
        IERC20(rdntDlp).safeTransferFrom(msg.sender, radiantStaking, _amount);
        IRadiantStaking(radiantStaking).stakeLp(_amount);

        _mintMDLP(_for, _amount, _mode);
    }

    /* ============ Internal Functions ============ */

    /// @notice deposit ETH/BNB in magpie finance and get mDLP at a 1:1 rate
    /// @param _mode 0 doing nothing, 1 is convert and stake
    function _mintMDLP(address _for, uint256 _amount, uint8 _mode) internal {
        if (_mode == STAKEMODE) {
            if (masterRadpie == address(0)) revert MasterRadpieNotSet();
            _mint(address(this), _amount);

            IERC20(address(this)).safeApprove(address(masterRadpie), _amount);
            IMasterRadpie(masterRadpie).depositFor(address(this), _for, _amount);

            emit mDLPConverted(_for, _amount, _mode);
        } else {
            _mint(_for, _amount);
            emit mDLPConverted(msg.sender, _amount, 0);
        }
    }

    /* ============ Admin Functions ============ */

    function pause() external onlyOwner {
        _pause();
    }

    function unpause() external onlyOwner {
        _unpause();
    }

    function setRadiantStaking(address _radiantStaking) external onlyOwner {
        if (radiantStaking == address(0)) revert AddressZero();

        radiantStaking = _radiantStaking;
        emit RadiantStakingSet(radiantStaking);
    }
}

