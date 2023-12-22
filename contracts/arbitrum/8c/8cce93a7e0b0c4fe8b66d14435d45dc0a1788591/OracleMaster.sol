// SPDX-License-Identifier: MIT
pragma solidity ^0.8.2;
import { IOracleMaster } from "./IOracleMaster.sol";
import { IOracle } from "./IOracle.sol";
import "./Ownable.sol";

contract OracleMaster is IOracleMaster, Ownable {
	mapping(address => IOracle) public tokenOracles;

	function queryInfo(address token_) public view override returns (uint256 price_) {
		IOracle orcl = tokenOracles[token_];
		price_ = orcl.query();
	}

	function updateTokenOracle(address token_, address orcl_) public onlyOwner {
		IOracle orcl = IOracle(orcl_);
		require(orcl.token() == token_, "OM:TOKEN MISMTCH");
		require(orcl.query() != 0, "OM:ORCL INV");
		tokenOracles[token_] = orcl;
	}
}

