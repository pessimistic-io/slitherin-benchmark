// SPDX-License-Identifier: AGPL-3.0-or-later

pragma solidity ^0.8.11;

import "./ERC1967Proxy.sol";
import "./Ownable.sol";
import "./IAutobuyback.sol";

contract FeesManager is Ownable, ERC1967Proxy {

    uint256 public buyBurnFee;
    uint256 public buyDevFee;
    uint256 public buyTotalFees;

    uint256 public sellBurnFee;
    uint256 public sellDevFee;
    uint256 public sellTotalFees;

    IAutobuyback public autobuybackContract;
    address public autobuybackAddress;

	constructor(
		address _logic, 
		bytes memory _data
	) 
		payable 
		ERC1967Proxy(_logic, _data)
	{
		buyBurnFee = 2;
        buyDevFee = 2;
        buyTotalFees = buyBurnFee + buyDevFee;

        sellBurnFee = 4;
        sellDevFee = 4;
        sellTotalFees = sellBurnFee + sellDevFee;
	}

	function upgradeImplementation(address newImplementation) external onlyOwner {
		_upgradeTo(newImplementation);
	}
	
	function getImplementation() external view returns (address) {
		return _getImplementation();
	}
}

