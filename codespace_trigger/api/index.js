module.exports = async (req, res) => {
  // Check for POST method
  if (req.method !== 'POST') {
    return res.status(405).json({ error: 'Method Not Allowed' });
  }

  // Get credentials from Vercel Environment Variables
  const token = process.env.GITHUB_TOKEN;
  const codespaceName = process.env.CODESPACE_NAME;

  if (!token || !codespaceName) {
    return res.status(500).json({ error: 'GitHub Token or Codespace Name not configured in Vercel.' });
  }

  try {
    const response = await fetch(`https://api.github.com/user/codespaces/${codespaceName}/start`, {
      method: 'POST',
      headers: {
        'Authorization': `Bearer ${token}`,
        'Accept': 'application/vnd.github+json',
        'X-GitHub-Api-Version': '2022-11-28'
      }
    });

    if (response.ok) {
      return res.status(200).json({ success: true, message: 'Codespace is starting up! Give it 2 minutes.' });
    } else {
      const errorData = await response.json();
      return res.status(response.status).json({ error: 'GitHub API Error', details: errorData });
    }
  } catch (err) {
    return res.status(500).json({ error: 'Failed to trigger GitHub API', details: err.message });
  }
};
