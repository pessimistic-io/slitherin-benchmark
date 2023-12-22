//SPDX-License-Identifier: MIT

/**
 * @title Error reporter, Inspired by compound-v2 error reporter
 * @author https://github.com/rohallah12
 */
pragma solidity 0.8.17;

contract ErrorReporter {
	error Unauthorized();
	error ZeroAmount();
	error NotEnoughBalance();
	error InsufficientUnlockAmount();
	error LenghtNotSame();
	error NotAnStaker();
}

