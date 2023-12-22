// SPDX-License-Identifier: MIT

pragma solidity ^0.8.10;
import "./CheckContract.sol";
import "./SafeMath.sol";
import "./ERC20Permit.sol";

contract YOUToken is CheckContract, UERC20Permit {
	using SafeMath for uint256;

	// uint for use with SafeMath
	uint256 internal _1_MILLION = 1e24; // 1e6 * 1e18 = 1e24

	address public immutable treasury;

	constructor(
		address _treasurySig
	) UERC20Permit("Vesta", "YOU", 6, 0x3c2269811836af69497E5F486A85D7316753cf62) {
		require(_treasurySig != address(0), "Invalid Treasury Sig");
		treasury = _treasurySig;

		//Lazy Mint to setup protocol.
		//After the deployment scripts, deployer addr automatically send the fund to the treasury.
		_mint(msg.sender, _1_MILLION.mul(50));
		_mint(_treasurySig, _1_MILLION.mul(50));
	}
}

