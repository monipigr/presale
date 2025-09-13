// SPDX-License-Identifier: MIT

pragma solidity ^0.8.24;

import "../lib/openzeppelin-contracts/contracts/access/Ownable.sol";
import "../lib/openzeppelin-contracts/contracts/token/ERC20/IERC20.sol";
import "../lib/openzeppelin-contracts/contracts/token/ERC20/ERC20.sol";
import "../lib/openzeppelin-contracts/contracts/token/ERC20/utils/SafeERC20.sol";
import "../lib/openzeppelin-contracts/contracts/utils/ReentrancyGuard.sol";
import "./interfaces/IAggregator.sol";

contract Presale is Ownable, ReentrancyGuard {
    using SafeERC20 for IERC20;

    address public saleTokenAddress;
    address public usdcAddress;
    address public usdtAddress;
    address public fundsReceiverAddr;
    address public dataFeedAddress;
    uint256[][3] public phases; // matrix with X rows as number of fases and 3 cols [supply][price][time]
    uint256 public currentPhase; 
    uint256 public maxSupply; 
    uint256 public totalSold; 
    uint256 public startingTime;
    uint256 public endingTime;
    uint256 public immutable FEE_BPS = 200; // 200 bps = 2%
    uint256 public collectedETHFees;

    mapping(address => bool) public isBlacklisted; 
    mapping(address => uint256) public userTokensDeposited; 
    mapping(address => uint256) public collectedFees;

    event UserBlacklisted(address user);
    event UserUnblacklisted(address user);
    event EmergencyTokenWithdrawn(address token, uint256 amount);
    event EmergencyETHWithdrawn(uint256 amount);
    event TokensBought(address user, uint256 amount);
    event ETHBought(address user, uint256 amount);
    event TokensClaimed(address user, uint256 amount);
    event FeeWithdrawn(address token, uint256 amount);
    
    constructor(address _saleTokenAddress, address _usdcAddress, address _usdtAddress, address _fundsReceiverAddr, address _dataFeedAddress , uint256[][3] memory _phases, uint256 _maxSupply, uint256 _startingTime, uint256 _endingTime) Ownable(msg.sender) {
        saleTokenAddress = _saleTokenAddress;
        usdcAddress = _usdcAddress;
        usdtAddress = _usdtAddress;
        fundsReceiverAddr = _fundsReceiverAddr;
        dataFeedAddress = _dataFeedAddress;
        phases = _phases;
        maxSupply = _maxSupply;
        startingTime = _startingTime;
        endingTime = _endingTime;

        require(endingTime > startingTime, "Incorrect presale times");
    }

    /**
     * @notice Add a user to the blacklist
     * @dev Only callable by the owner
     * @param _user Address of the user to add to the blacklist 
     */
    function blacklist(address _user) external onlyOwner {
        isBlacklisted[_user] = true;

        emit UserBlacklisted(_user);
    }

    /**
     * @notice Remove a user of the blacklist
     * @dev Only callable by the owner
     * @param _user Address of the user to remove from the blacklist
     */
    function unBlacklist(address _user) external onlyOwner {
        isBlacklisted[_user] = false;

        emit UserUnblacklisted(_user);
    }

    /**
     * @notice Allows a user to buy presale tokens using supported stablecoins
     * @param _tokenUsedToBuy The address of the stablecoin (USDC or USDT) used for payment.
     * @param _amount The amount of stablecoin tokens to spend (6 decimals for USDC/USDT).
     * @dev Updates user allocation, increases total sold amount, and transfers payment tokens to the funds receiver.
     */
    function buyWithTokens(address _tokenUsedToBuy, uint256 _amount) external nonReentrant {
        require(_amount > 0, "Zero amount");
        require(!isBlacklisted[msg.sender], "User is blacklisted");
        require(block.timestamp >= startingTime && block.timestamp <= endingTime, "Presale inactive");
        require(_tokenUsedToBuy == usdcAddress || _tokenUsedToBuy == usdtAddress, "Not Accepted Token");

        uint256 collectedFee = _amount * FEE_BPS / 10000;
        uint256 netAmount = _amount - collectedFee;
        collectedFees[_tokenUsedToBuy] += collectedFee;

        uint256 tokenAmountToReceive;
        if (ERC20(_tokenUsedToBuy).decimals() == 18) {
            tokenAmountToReceive = netAmount * 1e6 / phases[currentPhase][1];
        } else {
            // Generalized formula to normalize any payment token decimals to 18
            tokenAmountToReceive = netAmount * 10**(18 - ERC20(_tokenUsedToBuy).decimals()) * 1e6 / phases[currentPhase][1];
        }

        checkCurrentPhase(tokenAmountToReceive);

        require(totalSold <= maxSupply, "Max supply reached");
        totalSold += tokenAmountToReceive;

        userTokensDeposited[msg.sender] += tokenAmountToReceive;
        IERC20(_tokenUsedToBuy).safeTransferFrom(msg.sender, fundsReceiverAddr, netAmount);
        IERC20(_tokenUsedToBuy).safeTransferFrom(msg.sender, address(this), collectedFee);

        emit TokensBought(msg.sender, netAmount);
    }

    /**
     * @notice Allows a user to buy presale tokens using Ether
     * @dev Chainlink oracle used to calculate ether price
     */
    function buyWithETH() external payable nonReentrant {
        require(msg.value > 0, "Zero amount");
        require(!isBlacklisted[msg.sender], "User is blacklisted");
        require(block.timestamp >= startingTime && block.timestamp <= endingTime, "Presale not started yet");

        uint collectedETHFee = msg.value * FEE_BPS / 10000;
        uint netValue = msg.value - collectedETHFee;
        collectedETHFees += collectedETHFee;

        uint256 usdValue = netValue * getEtherPrice() / 1e18;
        uint256 tokenAmountToReceive = usdValue * 1e6 /phases[currentPhase][1];
        
        checkCurrentPhase(tokenAmountToReceive);

        require(totalSold <= maxSupply, "Max supply reached");
        totalSold += tokenAmountToReceive;

        userTokensDeposited[msg.sender] += tokenAmountToReceive;

        (bool success,) = fundsReceiverAddr.call{value: netValue}("");
        require(success, "Transfer failed");

        emit ETHBought(msg.sender, msg.value);
    }

    /**
     * @notice Allows a user to claim presale tokens after the sale has ended.
     * @dev Transfers the allocated tokens to the caller and resets their allocation.
     */
    function claimTokens() external nonReentrant(){   
        require(block.timestamp > endingTime, "Claim period not started");

        uint256 tokenAmountToReceive = userTokensDeposited[msg.sender];
        require(tokenAmountToReceive > 0, "Nothing to claim");
        delete userTokensDeposited[msg.sender]; 

        IERC20(saleTokenAddress).safeTransfer(msg.sender, tokenAmountToReceive);

        emit TokensClaimed(msg.sender, tokenAmountToReceive);
    }

    /**
     * @notice Withdraw accumulated protocol fees (ERC20 or ETH) after the presale.
     * @dev Follows CEI patter
     * @param _token The token address to withdraw fees for, or address(0) for ETH.
     */
    function withdrawFees(address _token) external onlyOwner nonReentrant() {
        require(block.timestamp > endingTime, "Claim period not started");

        if (_token == address(0)) {
            uint256 ethAmount = collectedETHFees;
            collectedETHFees = 0;
            (bool success,) = msg.sender.call{value: ethAmount}("");
            require(success, "Transfer failed");
            emit FeeWithdrawn(_token, ethAmount);
        } else {
            uint256 tokenAmount = collectedFees[_token];
            collectedFees[_token] = 0;
            IERC20(_token).safeTransfer(msg.sender, tokenAmount);
            emit FeeWithdrawn(_token, tokenAmount);
        }

    }

    /**
     * @notice Withdraw tokens from the contract in case of emergency
     * @dev Uses SafeERC20 to ensure transfer success. Only callable by the owner.
     * @param _tokenAddress Token address that owner wants to withdraw
     * @param _amount Amount of tokens to be withdrawn
     */
    function emergencyWithdrawTokens(address _tokenAddress, uint256 _amount) external onlyOwner nonReentrant {
        IERC20(_tokenAddress).safeTransfer(msg.sender, _amount);

        emit EmergencyTokenWithdrawn(_tokenAddress, _amount);
    }

    /**
     * @notice Withdraw the ether from the contract in case of emergency
     * @dev Only callable by the owner
     */
    function emergencyWithdrawETH() external onlyOwner nonReentrant {
        uint256 balance = address(this).balance;
        (bool success,) = msg.sender.call{value: balance}("");
        require(success, "Transfer failed");

        emit EmergencyETHWithdrawn(balance);
    }
    
    /**
     * @notice Checks if the presale should move to the next phase.
     * @dev Advances the current phase if either:
     *      - The total sold plus the current purchase exceeds the phase supply, OR
     *      - The current time has passed the phase deadline.
     *      Limited to 3 phases (0, 1, 2).
     * @param _amount The amount of presale tokens from the current purchase to evaluate against the phase cap.
     * @return phase The updated current phase index.
     */
    function checkCurrentPhase(uint256 _amount) private returns(uint256 phase) {
        if (_amount + totalSold >= phases[currentPhase][0] || block.timestamp >= phases[currentPhase][2] && currentPhase < 2) {
            currentPhase++;
            phase = currentPhase;
        } else {
            phase = currentPhase;
        }
    }

    /**
     * @notice Chainlink oracle to get the current eth/usd price conversion
     * @dev Returned price with 8 decimals according to the arbiscan ETH/USD 0x639Fe6ab55C921f74e7fac1ee960C0B6293ba612 contract
     */
    function getEtherPrice() public view returns(uint256) {
        (,int256 price,,,) = IAggregator(dataFeedAddress).latestRoundData();
        price = price * 1e10;
        return uint256(price);
    }

    /**
     * @notice Deposit sale tokens into the contract
     * @dev Uses SafeERC20 to ensure transfer success. Only callable by the owner.
     * @param amount Amount of sale tokens to deposit
     */
    function depositSaleTokens(uint256 amount) external onlyOwner {
        IERC20(saleTokenAddress).safeTransferFrom(msg.sender, address(this), amount);
    }

}
