// SPDX-License-Identifier: MIT

pragma solidity >=0.7.0;
import {ICurvePool} from "./ICurvePool.sol";
import {IERC20} from "./IERC20.sol";
import {ZeroCurveWrapper} from "./ZeroCurveWrapper.sol";
import {ICurveInt128} from "./ICurveInt128.sol";
import {ICurveInt256} from "./ICurveInt256.sol";
import {ICurveUInt128} from "./ICurveUInt128.sol";
import {ICurveUInt256} from "./ICurveUInt256.sol";
import {ICurveUnderlyingInt128} from "./ICurveUnderlyingInt128.sol";
import {ICurveUnderlyingInt256} from "./ICurveUnderlyingInt256.sol";
import {ICurveUnderlyingUInt128} from "./ICurveUnderlyingUInt128.sol";
import {ICurveUnderlyingUInt256} from "./ICurveUnderlyingUInt256.sol";
import {CurveLib} from "./CurveLib.sol";


contract ZeroCurveFactory {
	event CreateWrapper(address _wrapper);

	function createWrapper(
		bool _underlying,
		uint256 _tokenInIndex,
		uint256 _tokenOutIndex,
		address _pool
	) public payable {
		emit CreateWrapper(address(new ZeroCurveWrapper(_tokenInIndex, _tokenOutIndex, _pool, _underlying)));
	}
	fallback() payable external { /* no op */ }
}

