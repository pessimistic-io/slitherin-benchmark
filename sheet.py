from googleapiclient.discovery import build
from google.oauth2 import service_account

SCOPES = ['https://www.googleapis.com/auth/spreadsheets']

LETTERS_NUMBER = 26
def get_column_letters(n):
    result = ''
    while n >= 0:
        result = chr(ord('A') + n % LETTERS_NUMBER) + result
        n = n // LETTERS_NUMBER - 1
    return result
    
class Sheet:
    def __init__(self, service_account_file, sheet_id, sheet_name):
        credentials = service_account.Credentials.from_service_account_file(service_account_file, scopes=SCOPES)
        self.service = build('sheets', 'v4', credentials=credentials, cache_discovery=False)
        self.sheet_id = sheet_id
        self.sheet_name = sheet_name

    def get_sheets(self):
        return self.service.spreadsheets()

    def get_rows(self, sheet_range):
        sheets = self.get_sheets()
        result = sheets.values().get(
            spreadsheetId=self.sheet_id,
            range='{}!{}'.format(self.sheet_name, sheet_range)
        ).execute()
        # Get the last row number
        values = result.get('values', [])
        return values

    def add_row(self, row):
        sheets = self.get_sheets()
        column_letter = get_column_letters(len(row))
        sheet_range = f"A1:{column_letter}"
        body = {
            'values': [row]
        }
        result = sheets.values().append(
            spreadsheetId=self.sheet_id,
            range='{}!{}'.format(self.sheet_name, sheet_range),
            valueInputOption='USER_ENTERED',
            body=body
        ).execute()
        return result['updates'].get('updatedRows')

    def add_column(self, column_number, column_values):
        self.add_empty_column(column_number)
        sheets = self.get_sheets()

        # Get the letter of the specified column
        column_letter = get_column_letters(column_number)

        # Define the new column range
        num_rows = len(column_values)
        new_column_range = f'{column_letter}1:{column_letter}{num_rows}'
        # Update the values with the new column
        update_body = {
            'majorDimension': "COLUMNS",
            'values': [column_values],
        }
        results = sheets.values().update(
            spreadsheetId=self.sheet_id,
            range=f'{self.sheet_name}!{new_column_range}',
            body=update_body,
            valueInputOption="USER_ENTERED"
        ).execute()
        return results.get('updatedColumns')

    # Function to get the sheet ID by sheet name
    def get_sheet_info(self):
        sheet_metadata = self.service.spreadsheets().get(spreadsheetId=self.sheet_id).execute()
        sheets = sheet_metadata.get('sheets', [])
        for sheet in sheets:
            if sheet['properties']['title'] == self.sheet_name:
                self.sheet_list_id = sheet['properties']['sheetId']

                return sheet['properties']['sheetId'], sheet['properties']['gridProperties']['columnCount']
        return None

    def add_empty_column(self, column_index):
        sheet_list_id, columns_count = self.get_sheet_info()
        if column_index <= columns_count:
            body = {
                "requests": [
                    {
                        "insertDimension": {
                            "range": {
                                "sheetId": sheet_list_id,
                                "dimension": "COLUMNS",
                                "startIndex": column_index,
                                "endIndex": column_index + 1
                            },
                            "inheritFromBefore": False
                        }
                    }
                ]
            }
            self.service.spreadsheets().batchUpdate(spreadsheetId=self.sheet_id, body=body).execute()
