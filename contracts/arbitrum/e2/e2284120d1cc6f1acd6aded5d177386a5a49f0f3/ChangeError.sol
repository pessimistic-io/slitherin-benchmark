pragma solidity >=0.8.19;
/**
 * @title Library for change related errors.
 */

library ChangeError {
    /**
     * @dev Thrown when a change is expected but none is detected.
     */
    error NoChange();
}

