// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

/** 
 * @title TreasuryMock
 * @notice Minimal mock contract to act as funds receiver in tests.
 * @dev Accepts ETH transfers and emits an event when funds are received.
*/
contract MockTreasury {
    event FundsReceived(address indexed from, uint256 amount);

    receive() external payable {
        emit FundsReceived(msg.sender, msg.value);
    }
}
