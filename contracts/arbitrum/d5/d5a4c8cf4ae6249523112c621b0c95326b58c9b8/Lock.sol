// SPDX-License-Identifier: LGPL-3.0-only
pragma solidity 0.6.12;

import "./Ownable.sol";
import "./ERC20.sol";
import "./IERC20.sol";
import "./CupLPToken.sol";

contract Lock is Ownable, IERC20 {
    ERC20 public token;
    uint256 public lockDuration;

    CupLPToken public cuplp;
    string public name;
    string public symbol;
    uint256 public override totalSupply;
    mapping(address => uint256) public override balanceOf;

    function initialize(
        CupLPToken _cuplp,
        address _owner,
        address _token,
        uint256 _lockDuration,
        string memory _name,
        string memory _symbol
    ) public {
        cuplp = _cuplp;
        transferOwnership(_owner);
        token = ERC20(_token);
        lockDuration = _lockDuration;
        name = _name;
        symbol = _symbol;
        totalSupply = 0;
    }

    /// @dev Deposit tokens to be locked until the end of the locking period
    /// @param amount The amount of tokens to deposit
    function deposit(uint256 amount) public {
        balanceOf[msg.sender] += amount;
        totalSupply += amount;

        if (!token.transferFrom(msg.sender, address(this), amount)) {
             revert('transfer failed');
        }
        cuplp.mint(address(msg.sender), amount);
        emit Transfer(msg.sender, address(this), amount);
    }

    /// @dev Withdraw tokens after the end of the locking period or during the deposit period
    /// @param amount The amount of tokens to withdraw
    function withdraw(uint256 amount) public {
        if (
            block.timestamp < lockDuration
        ) {
             revert('lock perioud ongoing - failed');
        }
        if (balanceOf[msg.sender] < amount) {
            revert('exceeds bbalance');
        }

        balanceOf[msg.sender] -= amount;
        totalSupply -= amount;

        if (!token.transfer(msg.sender, amount)) {
            revert('transfer failed');
        }
        cuplp.burn(address(msg.sender), amount);
        emit Transfer(address(this), msg.sender, amount);
    }

    /// @dev Returns the number of decimals of the locked token
    function decimals() public view returns (uint8) {
        return token.decimals();
    }

    /// @dev Lock claim tokens are non-transferrable: ERC-20 transfer is not supported
    function transfer(address, uint256) external override returns (bool) {
        revert('not implemented - failed');
    }

    /// @dev Lock claim tokens are non-transferrable: ERC-20 allowance is not supported
    function allowance(address, address)
        external
        view
        override
        returns (uint256)
    {
      revert('not implemented - failed');
    }

    /// @dev Lock claim tokens are non-transferrable: ERC-20 approve is not supported
    function approve(address, uint256) external override returns (bool) {
       revert('not implemented - failed');
    }

    /// @dev Lock claim tokens are non-transferrable: ERC-20 transferFrom is not supported
    function transferFrom(
        address,
        address,
        uint256
    ) external override returns (bool) {
       revert('not implemented - failed');
    }
}

