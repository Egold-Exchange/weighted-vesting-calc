# GitHub Pages Setup Guide

Follow these steps to deploy your Vesting Calculator to GitHub Pages:

## Step 1: Commit and Push Your Files

```bash
# Add all new files
git add index.html README.md formula.md vesting-calculator.html

# Commit the changes
git commit -m "Add vesting calculator and documentation for GitHub Pages"

# Push to GitHub
git push origin main
```

## Step 2: Enable GitHub Pages

1. Go to your GitHub repository: `https://github.com/YOUR_USERNAME/bitswap-contract`

2. Click on **Settings** (top right of the repository)

3. Scroll down to **Pages** in the left sidebar

4. Under **Source**, select:
   - **Branch**: `main`
   - **Folder**: `/ (root)`

5. Click **Save**

6. Wait 1-2 minutes for GitHub to build your site

7. Your calculator will be live at:
   ```
   https://YOUR_USERNAME.github.io/bitswap-contract/
   ```

## Alternative: Using docs folder (Optional)

If you prefer to use a `docs` folder instead:

```bash
# Create docs folder and move index.html
mkdir docs
cp vesting-calculator.html docs/index.html

# Commit and push
git add docs/
git commit -m "Add docs folder for GitHub Pages"
git push origin main
```

Then in GitHub Settings > Pages, select:
- **Branch**: `main`
- **Folder**: `/docs`

## Step 3: Update README

Don't forget to update the README.md with your actual GitHub username:

```markdown
Visit the **[Vesting Calculator](https://YOUR_USERNAME.github.io/bitswap-contract/)** to see the weighted average vesting system in action!
```

## Step 4: Test Your Site

After deployment:
1. Visit your GitHub Pages URL
2. Click "Load Example" to test with your actual vesting data
3. Use the slider to simulate vesting over time
4. Share the link with your team!

## Troubleshooting

### Site not loading?
- Wait 2-5 minutes after enabling Pages
- Check that `index.html` is in the root (or `docs/index.html` if using docs folder)
- Make sure GitHub Pages is enabled in Settings

### Calculator not working?
- Check browser console for errors (F12)
- Try a hard refresh: Ctrl+Shift+R (Windows/Linux) or Cmd+Shift+R (Mac)

### Need to update the calculator?
```bash
# Make your changes to vesting-calculator.html
# Copy to index.html
cp vesting-calculator.html index.html

# Commit and push
git add index.html
git commit -m "Update calculator"
git push origin main

# Changes will appear in 1-2 minutes
```

## Custom Domain (Optional)

To use a custom domain:
1. Add a `CNAME` file in the root with your domain name
2. Configure DNS with your domain provider
3. See [GitHub's custom domain guide](https://docs.github.com/en/pages/configuring-a-custom-domain-for-your-github-pages-site)

---

🎉 That's it! Your vesting calculator is now live on GitHub Pages!
