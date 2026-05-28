
import { Request, Response } from 'express';
import { ExpenseService } from '../services/expense.service';
import { logger } from './logger';

const expenseService = new ExpenseService();

export const getExpenses = async (req: Request, res: Response) => {
  try {
    const expenses = await expenseService.getAllExpenses();
    res.status(200).json(expenses);
  } catch (error) {
    const errorMessage = error instanceof Error ? error.message : 'Unknown error';
    logger.error('request_error', { error_message: errorMessage });
    res.status(500).json({ error: 'Failed to fetch expenses' });
  }
};

export const addExpense = async (req: Request, res: Response) => {
  try {
    const { name, amount, category } = req.body;
    const expense = await expenseService.createExpense({ name, amount, category });
    logger.info('request_success', { message: 'Expense created successfully', expense });
    res.status(201).json(expense);
  } catch (error) {
    const errorMessage = error instanceof Error ? error.message : 'Unknown error';
    logger.error('request_error', { error_message: errorMessage });
    res.status(500).json({ error: 'Failed to create expense' });
  }
};
