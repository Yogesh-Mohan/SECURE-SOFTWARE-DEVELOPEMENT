# Gmail OTP Setup Guide

## Problem Solved ✅
Your app now sends **6-digit OTP codes** to the user's email (Gmail), and users paste the code back into the app to verify their email.

## Setup Steps

### Step 1: Enable 2-Factor Authentication on Gmail
1. Go to [myaccount.google.com](https://myaccount.google.com)
2. Click **Security** (left sidebar)
3. Scroll to **How you sign in to Google**
4. Click **2-Step Verification** → **Get Started**
5. Follow the prompts (very quick!)

### Step 2: Create an App Password
1. Go back to [myaccount.google.com](https://myaccount.google.com)
2. Click **Security** (left sidebar)
3. Scroll down to **App passwords** (only appears after 2FA is enabled)
4. Select:
   - App: **Mail**
   - Device: **Windows/Mac/Linux** (or your OS)
5. Click **Generate**
6. Google will show a 16-character password. **Copy this exactly** (spaces included)

### Step 3: Update Backend Environment
1. Create a `.env` file in the `backend/` folder (copy from `.env.example`):

```powershell
# backend/.env

DATABASE_NAME=adminsoftware-developement
MONGO_URL=mongodb://localhost:27017
SECRET_KEY=your-super-secret-key-1234567890

# Gmail OTP Configuration
SENDER_EMAIL=your-email@gmail.com
SENDER_PASSWORD=xxxx xxxx xxxx xxxx
```

**Important:**
- `SENDER_EMAIL`: Your Gmail address (e.g., `warayogesh2@gmail.com`)
- `SENDER_PASSWORD`: The 16-character App Password from Step 2 (includes spaces)

### Step 4: Test OTP System

#### Start Backend:
```powershell
cd backend
& ".\.venv\Scripts\Activate.ps1"
python -m uvicorn main:app --reload --port 8000
```

#### Test in Flutter:
1. Open the app
2. Go to Registration  
3. Enter: name, email (Gmail address), password, role
4. Click **SEND OTP**
5. Check your Gmail inbox (wait 5-10 seconds)
6. Copy the 6-digit OTP code
7. Paste into the app
8. Click **VERIFY OTP**

## Troubleshooting

### ❌ "Error sending OTP email"
- **Check:** Did you use the App Password (not your Gmail password)?
- **Check:** Is 2-Factor Authentication enabled?
- **Check:** Is `.env` file created with correct credentials?

### ❌ "Message not sent"
- Restart the backend server after updating `.env`
- Check MongoDB is running

### ❌ "Gmail blocked the email"
- Google sometimes blocks emails from new IPs/devices
- Solution: Log in to Gmail once from this device to approve it

### ❌ "OTP expired"
- OTP is only valid for **10 minutes**
- Click **Resend OTP** to get a new code

## Flow Summary

```
User Registration Flow:
1. User enters: Name, Email, Password, Role
2. App calls: /register-initiate endpoint
3. Backend generates: 6-digit OTP
4. Backend sends: OTP to Gmail via SMTP
5. User receives: Email with OTP code
6. User pastes: OTP into app
7. App calls: /verify-otp endpoint
8. Backend verifies: OTP is correct & not expired
9. Backend creates: User account
10. App navigates: To Dashboard (auto-login)
```

## Features

✅ **6-digit OTP** - Easy to remember and type  
✅ **10-minute expiry** - Secure  
✅ **5 resend attempts** - Prevents spam  
✅ **Beautiful HTML emails** - Professional look  
✅ **Attempt limiting** - 5 wrong attempts = blocked  
✅ **Gmail SMTP** - Free, reliable, no SendGrid needed  

## Environment Variables Reference

| Variable | Example | Notes |
|----------|---------|-------|
| `SENDER_EMAIL` | warayogesh2@gmail.com | Your Gmail address |
| `SENDER_PASSWORD` | xxxx xxxx xxxx xxxx | 16-char App Password (not Gmail password!) |
| `DATABASE_NAME` | adminsoftware-developement | MongoDB database name |
| `MONGO_URL` | mongodb://localhost:27017 | MongoDB connection string |
| `SECRET_KEY` | your-super-secret-key | JWT secret key |

## Next Steps

1. ✅ Setup Gmail App Password (above)
2. ✅ Create `.env` file in `backend/` folder
3. ✅ Restart backend server
4. ✅ Test OTP registration in app
5. ✅ Test OTP login
6. ⚡ Deploy to production (update `.env` with production Gmail account)

---

**Questions?** Check the error messages - they're descriptive!
