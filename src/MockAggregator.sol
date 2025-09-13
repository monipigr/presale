// SPDX-License-Identifier: MIT

pragma solidity ^0.8.24;

contract MockAggregator {
    int256 private _answer;

    constructor(int256 initialAnswer) {
        _answer = initialAnswer;
    }

    function latestRoundData() external view returns (uint80, int256, uint256, uint256, uint80) {
        return (0, _answer, 0, 0, 0);
    }
}
