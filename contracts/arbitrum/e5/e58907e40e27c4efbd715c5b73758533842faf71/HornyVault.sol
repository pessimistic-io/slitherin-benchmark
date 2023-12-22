// SPDX-License-Identifier: MIT

pragma solidity 0.8.13;

import "./IERC20.sol";
import "./ERC20.sol";
import "./SafeERC20.sol";
import "./Ownable.sol";
import "./Context.sol";
import "./Address.sol";
import "./ReentrancyGuard.sol";

interface IStrategy { 
    function vault() external view returns (address);
    function want() external view returns (IERC20);
    function beforeDeposit() external;
    function deposit() external;
    function withdraw(uint256) external;
    function balanceOf() external view returns (uint256);
    function harvest() external;
    function retireStrat() external;
    function panic() external;
    function pause() external;
    function unpause() external;
    function paused() external view returns (bool);
}

pragma solidity 0.8.13;

contract HornyVault is ERC20, Ownable, ReentrancyGuard {
    using SafeERC20 for IERC20;

    struct StratCandidate {
        address implementation;
        uint proposedTime;
    }

    IStrategy public strategy;
    StratCandidate public stratCandidate;
    uint256 constant approvalDelay = 86400;
    uint256 deploymentTime;

    address public strategist;
    bool migrated = false;

    event NewStratCandidate(address implementation);
    event UpgradeStrat(address implementation);
    event StrategistMigration(bool boolean, address newStrategist);
    event IncaseTokensGetStuck(address caller, uint256 amount, address token);

    constructor (
        IStrategy _strategy,
        string memory _name,
        string memory _symbol
    ) ERC20(
        _name,
        _symbol
    ) {
        strategy = _strategy;
        strategist = msg.sender;
        deploymentTime = block.timestamp;
    }

    function want() public view returns (IERC20) {
        return IERC20(IStrategy(strategy).want());
    }

    function balance() public view returns (uint) {
        return want().balanceOf(address(this)) + IStrategy(strategy).balanceOf();
    }

    function available() public view returns (uint256) {
        return want().balanceOf(address(this));
    }

    function getPricePerFullShare() public view returns (uint256) {
        return totalSupply() == 0 ? 1e18 : balance() * 1e18 / totalSupply();
    }

    function depositAll() external {
        deposit(want().balanceOf(msg.sender));
    }

    function deposit(uint _amount) public nonReentrant {
        require(_amount > 0, "Invalid amount");
        IStrategy(strategy).beforeDeposit();

        uint256 _pool = balance();
        want().safeTransferFrom(msg.sender, address(this), _amount);
        earn();
        uint256 _after = balance();
        _amount = _after - _pool; // Additional check for deflationary tokens
        uint256 shares = 0;
        if (totalSupply() == 0) {
            shares = _amount;
        } else {
            shares = (_amount * totalSupply()) / _pool;
        }
        _mint(msg.sender, shares);
    }

    function earn() internal {
        uint _bal = available();
        want().safeTransfer(address(strategy), _bal);
        IStrategy(strategy).deposit();
    }

    /**
     * @dev A helper function to call withdraw() with all the sender's funds.
     */
    function withdrawAll() external {
        withdraw(balanceOf(msg.sender));
    }

    /**
     * @dev Function to exit the system. The vault will withdraw the required tokens
     * from the strategy and pay up the token holder. A proportional number of IOU
     * tokens are burned in the process.
     */
    function withdraw(uint256 _shares) public {
        uint256 r = (balance() * _shares) / totalSupply();
        _burn(msg.sender, _shares);

        uint b = want().balanceOf(address(this));
        if (b < r) {
            uint _withdraw = r - b;
            IStrategy(strategy).withdraw(_withdraw);
            uint _after = want().balanceOf(address(this));
            uint _diff = _after - b;
            if (_diff < _withdraw) {
                r = b + _diff;
            }
        }

        want().safeTransfer(msg.sender, r);
    }

    /** 
     * @dev Sets the candidate for the new strat to use with this vault.
     * @param _implementation The address of the candidate strategy.  
     */
    function proposeStrat(address _implementation) public onlyOwner {
        require(address(this) == IStrategy(_implementation).vault(), "Proposal not valid for this Vault");
        stratCandidate = StratCandidate({
            implementation: _implementation,
            proposedTime: block.timestamp
         });

        emit NewStratCandidate(_implementation);
    }

    /** 
     * @dev It switches the active strat for the strat candidate. After upgrading, the 
     * candidate implementation is set to the 0x00 address, and proposedTime to a time 
     * happening in +100 years for safety. 
     */

    function upgradeStrat() public onlyOwner {
        require(stratCandidate.implementation != address(0), "There is no candidate");
        require(stratCandidate.proposedTime + approvalDelay < block.timestamp, "Delay has not passed");

        emit UpgradeStrat(stratCandidate.implementation);

        IStrategy(strategy).retireStrat();
        strategy = IStrategy(stratCandidate.implementation);
        stratCandidate.implementation = address(0);
        stratCandidate.proposedTime = 5000000000;

        earn();
    }

    /**
     * @dev Rescues random funds stuck that the strat can't handle.
     * @param _token address of the token to rescue.
     */
    function inCaseTokensGetStuck(address _token) external onlyOwner {
        require(_token != address(want()), "!token");

        uint256 amount = IERC20(_token).balanceOf(address(this));
        IERC20(_token).safeTransfer(msg.sender, amount);

        emit IncaseTokensGetStuck(msg.sender, amount, _token);
    }
}
