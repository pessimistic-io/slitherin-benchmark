// SPDX-License-Identifier: MIT

pragma solidity 0.8.13;

import "./IERC20.sol";
import "./ERC20.sol";
import "./Operator.sol";

/**
 *   A token voucher.
 *   The amount held by the user will not directly affect the user's funds within the system.
 */

contract Sharplabs is ERC20, Operator {
    address public riskOnPool;

    // flags
    bool public initialized;
    bool public isTransferForbidden = true;

    mapping(address => uint256) private _balances;

    mapping(address => mapping(address => uint256)) private _allowances;

    event Initialized(address indexed executor, uint256 at);

    modifier notInitialized() {
        require(!initialized, "already initialized");
        _;
    }

    constructor() ERC20("Sharplabs-wstETH", "Sharplabs-wstETH"){
    }

    function initialize(address _riskOnPool) public notInitialized {
        require(_riskOnPool != address(0), "riskOnPool address can not be zero address");
        riskOnPool = _riskOnPool;
        initialized = true;
        emit Initialized(msg.sender, block.number);
    }

    function mint(address account, uint256 amount) external {
        require(msg.sender == riskOnPool, "caller is not the pool");
        _mint(account, amount);
    }

    //  In case the user's tokens are lost or insufficient and they cannot withdraw funds (this will not affect the user's funds and the normal operation of the system).
    function mintByOperator(address account, uint256 amount) external onlyOperator {  
        _mint(account, amount);
    }

    function burn(address account, uint256 amount) external {
        require(msg.sender == riskOnPool, "caller is not the pool");
        _burn(account, amount);
    }
    
    function _transfer(address from, address to, uint256 amount) internal override {
        require(!isTransferForbidden, "transfer is forbidden");
        super._transfer(from, to, amount);
    }

    function forbidTransfer() external onlyOperator {
        require(!isTransferForbidden, "transfer has been forbidden");
        isTransferForbidden = true;
    }

    function allowTransfer() external onlyOperator {
        require(isTransferForbidden, "transfer has been allowed");
        isTransferForbidden = false;
    }

    function governanceRecoverUnsupported(
        IERC20 _token,
        uint256 _amount,
        address _to
    ) external onlyOperator {
        require(_to != address(0), "zero");
        _token.transfer(_to, _amount);
    }
}
