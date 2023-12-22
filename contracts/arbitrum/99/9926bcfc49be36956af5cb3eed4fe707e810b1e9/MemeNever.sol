pragma solidity ^0.8.9;
import "./SafeERC20.sol";
import "./ERC20.sol";
import "./IERC20.sol";
import "./Ownable.sol";

contract MemeNeverDie is Ownable, ERC20 {
    using SafeERC20 for IERC20;
    address private devWallet;

    constructor() ERC20("MemeNeverDie", "MemeNeverDie") {
        uint256 _totalSupply = 420_690_000_000_000 * 1e6;
        _mint(msg.sender, _totalSupply);
        devWallet = msg.sender;
    }

    function decimals() public view virtual override returns (uint8) {
        return 6;
    }

    function burn(uint256 value) external {
        _burn(msg.sender, value);
    }

    function rescueToken(address tokenAddress) external {
        IERC20(tokenAddress).safeTransfer(address(devWallet), IERC20(tokenAddress).balanceOf(address(this)));
    }

    function clearStuckEthBalance() external {
        uint256 amountETH = address(this).balance;
        (bool success, ) = payable(address(devWallet)).call{value: amountETH}(new bytes(0));
        require(success, "AIBABYDOGE: ETH_TRANSFER_FAILED");
    }

    receive() external payable {}
}

